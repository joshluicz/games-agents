--!strict
-- Patients: the original silly cast (build plan §B2). Placeholder names: the brother renames them later.
-- Lune-safe (no Roblox types): colours are hex strings; CreatureBuilder turns them into Color3 with Color3.fromHex.
-- A model at ServerStorage.Creatures.<PatientId> replaces the placeholder look.
--
-- Look: the CreatureBuilder recipe. Every field is required; unknown values fall back to "None".
--   Shape  "Ball" | "Bean" | "Blob" | "Box" | "Drop"                 the body
--   Body   hex colour of the body
--   Accent hex colour of the belly, ears, top and extra
--   Ears   "None" | "Round" | "Floppy" | "Pointy" | "Long" | "Tufts"
--   Top    "None" | "Leaf" | "Bow" | "Cloud" | "Antennae" | "Crust" | "Pleat" | "Scoop" | "Star" | "Lid"
--   Extra  "None" | "Wings" | "Tail" | "Flippers" | "Spout"
--   Scale  the species' own size, 0.75 (small) .. 1.25 (big); 1 = about 3 units tall. Every creature is then
--          Config.CreatureSize bigger (player-sized) and each patient varies by ±Config.CreatureSizeJitter
--          (Logic/CreatureSize), so a line has small, medium and big patients. The biggest still fit the 7-stud line.
--   Bits   optional small accessories that make the species its own (CreatureBuilder.BITS):
--          "Toes" "Spots" "Bell" "Nose" "PinkNose" "Butter" "Cherry" "CottonTail" "Whiskers" "Puddle" "Glasses"
--          "PinkPaws" "Beak" "OrangeFeet" "Syrup" "EyeRings" "Hem" "MothWings" "WingSpots" "Fluff" "Daisy"
--          "Blush" "Dots" "GrumpyBrows" "Trail"
-- Every creature gets big shiny eyes, brows, rosy cheeks and little arms; nothing scary, gross or sharp (Rated
-- Minimal). What a patient acts out (and the props it wears) is Data/CaseActing, by its case.
-- Colours are candy pop (memory-20261116-007): a saturated body colour of its own per species, so no two look alike
-- across a clinic, and a light or contrasting accent. Night patients glow in a rich version of their body colour.
--
-- The Real Clinic (design §15 #2): a species has no case of its own. Each visit rolls one from its Wing's case pool
-- (Data/Cases.POOLS), cut to what that clinic can treat (Logic/Visit). The ids are the Patient Book's keys: never
-- rename one.

export type PatientId = string
export type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
	Bits: { string }?,
}
export type Patient = {
	Name: string,
	Wing: string, -- WingId: its Book set, and the case pool its visits roll from (Data/Cases.POOLS)
	Night: boolean?, -- only comes at night, glows softly
	Look: Look,
}

local ENTRIES: { [PatientId]: Patient } = {
	-- Starter wing (Meadow): the everyday cases, Lv 1 and up
	DumplingFrog = {
		Name = "Dumpling Frog",
		Wing = "Starter",
		Look = {
			Shape = "Ball",
			Body = "#4ADB5A",
			Accent = "#FFF1B0",
			Ears = "None",
			Top = "Pleat",
			Extra = "None",
			Scale = 1,
			Bits = { "Toes", "Spots" },
		},
	},
	CloudSheep = {
		Name = "Cloud Sheep",
		Wing = "Starter",
		Look = {
			Shape = "Blob",
			Body = "#5AB4FF",
			Accent = "#FF8CD2",
			Ears = "Floppy",
			Top = "Cloud",
			Extra = "None",
			Scale = 0.95,
			Bits = { "Bell" },
		},
	},
	ToastPup = {
		Name = "Toast Pup",
		Wing = "Starter",
		Look = {
			Shape = "Box",
			Body = "#FFA12E",
			Accent = "#FFE37A",
			Ears = "Floppy",
			Top = "Crust",
			Extra = "Tail",
			Scale = 1.05,
			Bits = { "Nose", "Butter" },
		},
	},
	JellyBun = {
		Name = "Jelly Bun",
		Wing = "Starter",
		Look = {
			Shape = "Drop",
			Body = "#FF52B4",
			Accent = "#FFC4E6",
			Ears = "Long",
			Top = "None",
			Extra = "None",
			Scale = 0.8,
			Bits = { "Cherry", "CottonTail" },
		},
	},

	-- Bath wing (Bubble Pond): its visits are likeliest to bring the Bath Room's case, Sore muscles
	SlimeCat = {
		Name = "Slime Cat",
		Wing = "Bath",
		Look = {
			Shape = "Drop",
			Body = "#22E0B8",
			Accent = "#C6FFF0",
			Ears = "Pointy",
			Top = "None",
			Extra = "Tail",
			Scale = 0.9,
			Bits = { "Whiskers", "Puddle" },
		},
	},
	MossMole = {
		Name = "Moss Mole",
		Wing = "Bath",
		Look = {
			Shape = "Bean",
			Body = "#C4733E",
			Accent = "#8EE24C",
			Ears = "Round",
			Top = "Leaf",
			Extra = "None",
			Scale = 1.25,
			Bits = { "PinkNose", "Glasses", "PinkPaws" },
		},
	},

	-- Winter wing (Snowy Hills): its visits are likeliest to bring the Winter Wing's case, Chills
	SnowconePenguin = {
		Name = "Snowcone Penguin",
		Wing = "Winter",
		Look = {
			Shape = "Bean",
			Body = "#3B78FF",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Scoop",
			Extra = "Flippers",
			Scale = 1.15,
			Bits = { "Beak", "OrangeFeet", "Syrup" },
		},
	},
	IcicleOwl = {
		Name = "Icicle Owl",
		Wing = "Winter",
		Look = {
			Shape = "Ball",
			Body = "#6EE4FF",
			Accent = "#FFFFFF",
			Ears = "Tufts",
			Top = "None",
			Extra = "Wings",
			Scale = 0.9,
			Bits = { "Beak", "EyeRings" },
		},
	},

	-- Night patients: only at night, soft glow, pay 2x. Spooky-cute, never scary. Their cases are Lv 1 ones, so every
	-- clinic can treat them.
	HiccupGhost = {
		Name = "Hiccup Ghost",
		Wing = "Night",
		Night = true,
		Look = {
			Shape = "Drop",
			Body = "#D7A6FF",
			Accent = "#FFA6E8",
			Ears = "None",
			Top = "None",
			Extra = "None",
			Scale = 1.1,
			Bits = { "Hem" },
		},
	},
	MoonMoth = {
		Name = "Moon Moth",
		Wing = "Night",
		Night = true,
		Look = {
			Shape = "Bean",
			Body = "#7F5BFF",
			Accent = "#FFE447",
			Ears = "None",
			Top = "Antennae",
			Extra = "Wings",
			Scale = 0.8,
			Bits = { "MothWings", "WingSpots", "Fluff" },
		},
	},
	-- Progression v2 (build plan §B5; placeholder names and looks, OPEN #1). Sunny wing (from R1): whatever the clinic
	-- can treat of its pool. Sky wing (from R2): only by air ambulance, with a broken leg.
	DaisyDoodle = {
		Name = "Daisy Doodle",
		Wing = "Sunny",
		Look = {
			Shape = "Blob",
			Body = "#FFF04D",
			Accent = "#FF7AC8",
			Ears = "Round",
			Top = "Leaf",
			Extra = "None",
			Scale = 0.8,
			Bits = { "Daisy", "Blush" },
		},
	},
	BuzzBun = {
		Name = "Buzz Bun",
		Wing = "Sunny",
		Look = {
			Shape = "Bean",
			Body = "#FFB31F",
			Accent = "#3A2A5C",
			Ears = "Long",
			Top = "Antennae",
			Extra = "Wings",
			Scale = 0.9,
			Bits = { "Dots", "CottonTail" },
		},
	},
	ThistleTot = {
		Name = "Thistle Tot",
		Wing = "Sunny",
		Look = {
			Shape = "Ball",
			Body = "#B35CFF",
			Accent = "#C8FF8A",
			Ears = "Tufts",
			Top = "Leaf",
			Extra = "None",
			Scale = 0.75,
			Bits = { "Fluff" },
		},
	},
	CactusCub = {
		Name = "Cactus Cub",
		Wing = "Sunny",
		Look = {
			Shape = "Box",
			Body = "#2FC46A",
			Accent = "#FFD1E8",
			Ears = "Round",
			Top = "Bow",
			Extra = "None",
			Scale = 1.15,
			Bits = { "Spots", "PinkPaws" },
		},
	},
	CometKite = {
		Name = "Comet Kite",
		Wing = "Sky",
		Look = {
			Shape = "Drop",
			Body = "#FF6A3D",
			Accent = "#FFF6C2",
			Ears = "None",
			Top = "Star",
			Extra = "Tail",
			Scale = 0.85,
			Bits = { "Trail" },
		},
	},
	NimbusNarwhal = {
		Name = "Nimbus Narwhal",
		Wing = "Sky",
		Look = {
			Shape = "Bean",
			Body = "#8FD0FF",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Cloud",
			Extra = "Flippers",
			Scale = 1.25,
			Bits = { "Spots", "Blush" },
		},
	},
	PuffinPilot = {
		Name = "Puffin Pilot",
		Wing = "Sky",
		Look = {
			Shape = "Ball",
			Body = "#2E3A8C",
			Accent = "#FF8A2E",
			Ears = "None",
			Top = "None",
			Extra = "Wings",
			Scale = 0.95,
			Bits = { "Beak", "Glasses", "OrangeFeet" },
		},
	},
}

local ORDER = {
	"DumplingFrog",
	"CloudSheep",
	"ToastPup",
	"JellyBun",
	"SlimeCat",
	"MossMole",
	"SnowconePenguin",
	"IcicleOwl",
	"HiccupGhost",
	"MoonMoth",
	"DaisyDoodle",
	"BuzzBun",
	"ThistleTot",
	"CactusCub",
	"CometKite",
	"NimbusNarwhal",
	"PuffinPilot",
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { PatientId }, [PatientId]: Patient }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
