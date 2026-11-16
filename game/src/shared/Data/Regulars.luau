--!strict
-- Regulars: three returning patients with a 5-beat story each (build plan §B2, design §5.7).
-- A story day is a real UTC calendar day: at most one beat per regular per day, and beats wait for you.
-- Each beat is told with an emote and a speech bubble of 6 words or fewer. Lune-safe (no Roblox types).
--
-- `Patient` is the creature id: CreatureBuilder.build(Patient) uses this entry's `Look` (same recipe as
-- Data/Patients) or a model at ServerStorage.Creatures.<Patient>.
-- `Ailment` must be treatable at the First-Aid Stand (Remedy or Plaster), so every clinic can cure them.

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
		Look = {
			Shape = "Bean",
			Body = "#B7E07A",
			Accent = "#FFF6D8",
			Ears = "None",
			Top = "Leaf",
			Extra = "None",
			Scale = 0.8,
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
		Look = {
			Shape = "Ball",
			Body = "#E98A7B",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Lid",
			Extra = "Spout",
			Scale = 1,
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
		Look = {
			Shape = "Ball",
			Body = "#FFE27A",
			Accent = "#FFB547",
			Ears = "None",
			Top = "Star",
			Extra = "Tail",
			Scale = 0.9,
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
