--!strict
-- Regulars: three returning patients with a 5-beat story each (build plan §B2, design §5.7).
-- A story day is a real UTC calendar day: at most one beat per regular per day, and beats wait for you.
-- Each beat is told with an emote and a speech bubble of 6 words or fewer. Lune-safe (no Roblox types).
--
-- `Patient` is the creature id: CreatureBuilder.build(Patient) uses this entry's `Look` (same recipe as
-- Data/Patients, with the same candy-pop colours, sizes and Bits) or a model at ServerStorage.Creatures.<Patient>.
-- `Ailment` must be treatable at the First-Aid Stand (Remedy or Plaster), so every clinic can cure them.
-- `Recipe` is their own (depth update §1: "regulars their own"): First-Aid Stand items only, item 1 = the ailment's
-- station item. The hospital level cuts it like any recipe (Lv 1 -> 1 item), so these are the game's 3-item recipes.

export type RegularId = string
export type Beat = { Emote: string, Bubble: string }
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
export type Regular = {
	Name: string,
	Patient: string, -- creature id (equals the RegularId)
	Ailment: string, -- AilmentId
	Wing: string, -- WingId, for the Book
	UnlockStars: number, -- Clinic Stars needed before they start visiting
	Beats: { Beat }, -- exactly 5
	Reward: string, -- DecorId or RoomId, granted when the story finishes
	RewardKind: "Decor" | "Room",
	Recipe: { string }, -- ItemIds, 1-3 (Stand items only)
	Look: Look,
}

local ENTRIES: { [RegularId]: Regular } = {
	-- Scared of the clinic, then becomes your mascot.
	ShySprout = {
		Name = "Shy Sprout",
		Patient = "ShySprout",
		Ailment = "Sneezes",
		Wing = "Starter",
		UnlockStars = 0,
		Beats = {
			{ Emote = "🙈", Bubble = "Eek! Is it safe in there?" },
			{ Emote = "👀", Bubble = "I peeked inside. So cozy!" },
			{ Emote = "🤧", Bubble = "Achoo! You always help me." },
			{ Emote = "🌼", Bubble = "I told all my friends!" },
			{ Emote = "🥰", Bubble = "Can I be your mascot?" },
		},
		Reward = "SproutMascot",
		RewardKind = "Decor",
		Recipe = { "Potion" },
		Look = {
			Shape = "Bean",
			Body = "#A6EA38",
			Accent = "#FFF6C4",
			Ears = "None",
			Top = "Leaf",
			Extra = "None",
			Scale = 0.75,
			Bits = { "Daisy", "Blush" },
		},
	},

	-- Grumpy at first, then gives you their lucky kettle.
	GrumpyTeapot = {
		Name = "Grumpy Teapot",
		Patient = "GrumpyTeapot",
		Ailment = "Hiccups",
		Wing = "Starter",
		UnlockStars = 40,
		Beats = {
			{ Emote = "😤", Bubble = "Hmph. Fix my hiccups. Quickly." },
			{ Emote = "😒", Bubble = "Fine. That was... not awful." },
			{ Emote = "♨️", Bubble = "Hic! Steam hiccups again. Hmph!" },
			{ Emote = "😊", Bubble = "Oops, I smiled. Don't tell!" },
			{ Emote = "🍀", Bubble = "Take my lucky kettle. Thanks!" },
		},
		Reward = "LuckyKettle",
		RewardKind = "Decor",
		Recipe = { "Potion", "Plaster", "Potion" },
		Look = {
			Shape = "Ball",
			Body = "#FF5A62",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Lid",
			Extra = "Spout",
			Scale = 0.9,
			Bits = { "Dots", "GrumpyBrows" },
		},
	},

	-- Lost, finds the way home, and leaves a glow that lights up your clinic at night.
	DizzyComet = {
		Name = "Dizzy Comet",
		Patient = "DizzyComet",
		Ailment = "Bump",
		Wing = "Night",
		UnlockStars = 120,
		Beats = {
			{ Emote = "😵", Bubble = "Whoa! Which way is up?" },
			{ Emote = "🗺️", Bubble = "Still lost. Nice clinic, though!" },
			{ Emote = "🌙", Bubble = "Ooh, I can see the moon!" },
			{ Emote = "✨", Bubble = "I remember my way home!" },
			{ Emote = "🌠", Bubble = "Keep my glow. Goodnight, friend!" },
		},
		Reward = "CometLantern",
		RewardKind = "Decor",
		Recipe = { "Plaster", "Potion", "Plaster" },
		Look = {
			Shape = "Ball",
			Body = "#FFD52E",
			Accent = "#FF8A1E",
			Ears = "None",
			Top = "Star",
			Extra = "Tail",
			Scale = 0.85,
			Bits = { "Trail" },
		},
	},
}

local ORDER = { "ShySprout", "GrumpyTeapot", "DizzyComet" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { RegularId }, [RegularId]: Regular }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
