--!strict
-- Decor: preset items for the decor slots in your rooms (build plan §B2). Lune-safe (no Roblox types).
-- Price = nil means earned only, and EarnedBy says how: "Book" (a wing's set), "Story" (a regular), "Referral" or
-- "Playtime" (a Doctor rank from time played, Data/Playtime.Ranks) or "Journal" (a Nurse Journal rarity group,
-- Data/Rarities Journal.Decor).
-- Nothing here is random or paid with Robux.
--
-- Look: the DecorBuilder recipe (Task 7). A model at ServerStorage.ClinicKit.Decor.<DecorId> replaces it.
--   Kind   "Rug" | "Plant" | "Lamp" | "Balloons" | "Shelf" | "Bowl" | "Arch" | "Bench" | "Fountain"
--          | "Globe" | "Lantern" | "Statue" | "Kettle"
--   Color  main hex colour · Accent second hex colour · Glow true = softly lit at night
-- Decor models fit a 4 x 4 stud footprint and are pivoted at their bottom centre.

export type DecorId = string
export type DecorLook = {
	Kind: string,
	Color: string,
	Accent: string,
	Glow: boolean?,
}
export type Decor = {
	Name: string,
	Icon: string,
	Price: number?,
	EarnedBy: string?,
	Look: DecorLook,
}

local ENTRIES: { [DecorId]: Decor } = {
	-- In the shop
	PottedFern = {
		Name = "Potted Fern",
		Icon = "🌿",
		Price = 60,
		Look = { Kind = "Plant", Color = "#6FBF73", Accent = "#D9825B" },
	},
	CozyRug = {
		Name = "Cozy Rug",
		Icon = "🧶",
		Price = 80,
		Look = { Kind = "Rug", Color = "#F2A65A", Accent = "#FFE3B8" },
	},
	BubbleLamp = {
		Name = "Bubble Lamp",
		Icon = "💡",
		Price = 120,
		Look = { Kind = "Lamp", Color = "#FFE9A8", Accent = "#8FC7E8", Glow = true },
	},
	BalloonBunch = {
		Name = "Balloon Bunch",
		Icon = "🎈",
		Price = 150,
		Look = { Kind = "Balloons", Color = "#FF8FA3", Accent = "#8FD3FF" },
	},
	ToyShelf = {
		Name = "Toy Shelf",
		Icon = "🧸",
		Price = 200,
		Look = { Kind = "Shelf", Color = "#C98F62", Accent = "#FFD36E" },
	},
	FishBowl = {
		Name = "Fish Bowl",
		Icon = "🐠",
		Price = 250,
		Look = { Kind = "Bowl", Color = "#BDEBFF", Accent = "#FF9F43" },
	},
	FlowerArch = {
		Name = "Flower Arch",
		Icon = "🌸",
		Price = 400,
		Look = { Kind = "Arch", Color = "#FFFFFF", Accent = "#FFB7D5" },
	},

	-- Earned: Patient Book wing sets (Data/Wings SetReward)
	HeartRug = {
		Name = "Heart Rug",
		Icon = "❤️",
		EarnedBy = "Book",
		Look = { Kind = "Rug", Color = "#FF6F91", Accent = "#FFD1DC" },
	},
	RubberDuckFountain = {
		Name = "Duck Fountain",
		Icon = "🦆",
		EarnedBy = "Book",
		Look = { Kind = "Fountain", Color = "#9ADCF5", Accent = "#FFD84D" },
	},
	SnowGlobeLamp = {
		Name = "Snow Globe Lamp",
		Icon = "☃️",
		EarnedBy = "Book",
		Look = { Kind = "Globe", Color = "#E6F4FF", Accent = "#8FB8E8", Glow = true },
	},
	MoonLantern = {
		Name = "Moon Lantern",
		Icon = "🌙",
		EarnedBy = "Book",
		Look = { Kind = "Lantern", Color = "#B9A7E8", Accent = "#FFF2A8", Glow = true },
	},

	-- Earned: regulars' stories (Data/Regulars Reward)
	SproutMascot = {
		Name = "Sprout Mascot",
		Icon = "🌱",
		EarnedBy = "Story",
		Look = { Kind = "Statue", Color = "#B7E07A", Accent = "#FFF6D8" },
	},
	LuckyKettle = {
		Name = "Lucky Kettle",
		Icon = "🍀",
		EarnedBy = "Story",
		Look = { Kind = "Kettle", Color = "#E98A7B", Accent = "#7BCB7B" },
	},
	CometLantern = {
		Name = "Comet Lantern",
		Icon = "🌠",
		EarnedBy = "Story",
		Look = { Kind = "Lantern", Color = "#FFE27A", Accent = "#FFB547", Glow = true },
	},

	-- Earned: completing a Nurse Journal rarity group (Data/Rarities Journal.Decor; Server/Nurses)
	PlasterRug = {
		Name = "Plaster Rug",
		Icon = "🩹",
		EarnedBy = "Journal",
		Look = { Kind = "Rug", Color = "#FFB3C7", Accent = "#FFFFFF" },
	},
	HeartLamp = {
		Name = "Heart Lamp",
		Icon = "💗",
		EarnedBy = "Journal",
		Look = { Kind = "Lamp", Color = "#FF6F91", Accent = "#FFE3EC", Glow = true },
	},
	StarFountain = {
		Name = "Star Fountain",
		Icon = "⭐",
		EarnedBy = "Journal",
		Look = { Kind = "Fountain", Color = "#C9A7FF", Accent = "#FFE066" },
	},
	RainbowArch = {
		Name = "Rainbow Arch",
		Icon = "🌈",
		EarnedBy = "Journal",
		Look = { Kind = "Arch", Color = "#FFFFFF", Accent = "#7FD4FF" },
	},
	MoonGlobe = {
		Name = "Moon Globe",
		Icon = "🔮",
		EarnedBy = "Journal",
		Look = { Kind = "Globe", Color = "#3B347A", Accent = "#FFE9A8", Glow = true },
	},
	GoldenStatue = {
		Name = "Golden Statue",
		Icon = "🏆",
		EarnedBy = "Journal",
		Look = { Kind = "Statue", Color = "#FFD84A", Accent = "#FFF6D8" },
	},

	-- Earned: a friend referral, once, for both players (Visits)
	FriendBench = {
		Name = "Friend Bench",
		Icon = "🛋️",
		EarnedBy = "Referral",
		Look = { Kind = "Bench", Color = "#8FD3B6", Accent = "#FFFFFF" },
	},

	-- Earned: Doctor ranks from time played, one each (Data/Playtime.Ranks, Server/Playtime)
	InternRug = {
		Name = "Intern Rug",
		Icon = "🩹",
		EarnedBy = "Playtime",
		Look = { Kind = "Rug", Color = "#7FDCC0", Accent = "#FFFFFF" },
	},
	ResidentFern = {
		Name = "Resident Fern",
		Icon = "🪴",
		EarnedBy = "Playtime",
		Look = { Kind = "Plant", Color = "#62C98A", Accent = "#8FB8FF" },
	},
	DoctorLantern = {
		Name = "Doctor Lantern",
		Icon = "🏮",
		EarnedBy = "Playtime",
		Look = { Kind = "Lantern", Color = "#FF9FB4", Accent = "#FFFFFF", Glow = true },
	},
	SeniorBench = {
		Name = "Senior Bench",
		Icon = "🪑",
		EarnedBy = "Playtime",
		Look = { Kind = "Bench", Color = "#9AB4FF", Accent = "#FFE27A" },
	},
	ChiefArch = {
		Name = "Chief's Arch",
		Icon = "🌟",
		EarnedBy = "Playtime",
		Look = { Kind = "Arch", Color = "#FFE27A", Accent = "#C9A7FF" },
	},
	LegendStatue = {
		Name = "Legend Statue",
		Icon = "🏆",
		EarnedBy = "Playtime",
		Look = { Kind = "Statue", Color = "#FFD84D", Accent = "#B9A7E8" },
	},
}

local ORDER = {
	"PottedFern",
	"CozyRug",
	"BubbleLamp",
	"BalloonBunch",
	"ToyShelf",
	"FishBowl",
	"FlowerArch",
	"HeartRug",
	"RubberDuckFountain",
	"SnowGlobeLamp",
	"MoonLantern",
	"SproutMascot",
	"LuckyKettle",
	"CometLantern",
	"PlasterRug",
	"HeartLamp",
	"StarFountain",
	"RainbowArch",
	"MoonGlobe",
	"GoldenStatue",
	"FriendBench",
	"InternRug",
	"ResidentFern",
	"DoctorLantern",
	"SeniorBench",
	"ChiefArch",
	"LegendStatue",
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { DecorId }, [DecorId]: Decor }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
