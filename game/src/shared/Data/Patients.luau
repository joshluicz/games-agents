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
--   Scale  1 = about 3 studs tall
-- Every creature gets big friendly eyes and rosy cheeks; nothing scary, gross or sharp (Rated Minimal).

export type PatientId = string
export type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
}
export type Patient = {
	Name: string,
	Ailment: string, -- AilmentId
	Wing: string, -- WingId
	Night: boolean?, -- only comes at night, glows softly
	Look: Look,
}

local ENTRIES: { [PatientId]: Patient } = {
	-- Starter wing: treatable at the First-Aid Stand
	DumplingFrog = {
		Name = "Dumpling Frog",
		Ailment = "Hiccups",
		Wing = "Starter",
		Look = {
			Shape = "Ball",
			Body = "#A8DB8F",
			Accent = "#FFF3D6",
			Ears = "None",
			Top = "Pleat",
			Extra = "None",
			Scale = 1,
		},
	},
	CloudSheep = {
		Name = "Cloud Sheep",
		Ailment = "Sneezes",
		Wing = "Starter",
		Look = {
			Shape = "Blob",
			Body = "#F5F7FF",
			Accent = "#9FB4D9",
			Ears = "Floppy",
			Top = "Cloud",
			Extra = "None",
			Scale = 1.05,
		},
	},
	ToastPup = {
		Name = "Toast Pup",
		Ailment = "Bump",
		Wing = "Starter",
		Look = {
			Shape = "Box",
			Body = "#E8B573",
			Accent = "#FFE7B3",
			Ears = "Floppy",
			Top = "Crust",
			Extra = "Tail",
			Scale = 1,
		},
	},
	JellyBun = {
		Name = "Jelly Bun",
		Ailment = "Scrape",
		Wing = "Starter",
		Look = {
			Shape = "Drop",
			Body = "#FF9EC7",
			Accent = "#FFD1E6",
			Ears = "Long",
			Top = "None",
			Extra = "None",
			Scale = 0.95,
		},
	},

	-- Bath wing: needs the Bath Room
	SlimeCat = {
		Name = "Slime Cat",
		Ailment = "Sticky",
		Wing = "Bath",
		Look = {
			Shape = "Drop",
			Body = "#8EE3C8",
			Accent = "#D9FFF2",
			Ears = "Pointy",
			Top = "None",
			Extra = "Tail",
			Scale = 1,
		},
	},
	MossMole = {
		Name = "Moss Mole",
		Ailment = "Muddy",
		Wing = "Bath",
		Look = {
			Shape = "Bean",
			Body = "#B08A72",
			Accent = "#9CCB86",
			Ears = "Round",
			Top = "Leaf",
			Extra = "None",
			Scale = 0.95,
		},
	},

	-- Winter wing: needs the Winter Wing room
	SnowconePenguin = {
		Name = "Snowcone Penguin",
		Ailment = "Chills",
		Wing = "Winter",
		Look = {
			Shape = "Bean",
			Body = "#7FA7E8",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Scoop",
			Extra = "Flippers",
			Scale = 1,
		},
	},
	IcicleOwl = {
		Name = "Icicle Owl",
		Ailment = "FrozenNose",
		Wing = "Winter",
		Look = {
			Shape = "Ball",
			Body = "#CFE6FF",
			Accent = "#FFFFFF",
			Ears = "Tufts",
			Top = "None",
			Extra = "Wings",
			Scale = 1,
		},
	},

	-- Night patients: only at night, soft glow, pay 2x. Spooky-cute, never scary.
	HiccupGhost = {
		Name = "Hiccup Ghost",
		Ailment = "Cough",
		Wing = "Night",
		Night = true,
		Look = {
			Shape = "Drop",
			Body = "#F3EEFF",
			Accent = "#C9B6FF",
			Ears = "None",
			Top = "None",
			Extra = "None",
			Scale = 1,
		},
	},
	MoonMoth = {
		Name = "Moon Moth",
		Ailment = "LostGlow",
		Wing = "Night",
		Night = true,
		Look = {
			Shape = "Bean",
			Body = "#B9A7E8",
			Accent = "#FFF2A8",
			Ears = "None",
			Top = "Antennae",
			Extra = "Wings",
			Scale = 0.95,
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
