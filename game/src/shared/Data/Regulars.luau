--!strict
-- Regulars: three returning patients with a 5-beat story each (build plan §B2, design §5.7).
-- A story day is a real UTC calendar day: at most one beat per regular per day, and beats wait for you.
-- Each beat is told with an emote and a speech bubble of 6 words or fewer. Lune-safe (no Roblox types).
--
-- `Patient` is the creature id: CreatureBuilder.build(Patient) uses this entry's `Look` (same recipe as
-- Data/Patients, with the same candy-pop colours, sizes and Bits) or a model at ServerStorage.Creatures.<Patient>.
-- `Case` is their one fixed case (Data/Cases; design §11: they keep their stories and get one case each). It is a
-- Lv 1 case with no Room, so every clinic can treat it (Logic/Visit.canTreat at Lv 1), and a regular goes through the
-- same visit as anyone: the exam, then its plan (cut by the hospital level), and from Lv 2-3 a ward rest if it Stays.
-- Their words fit their case: Shy Sprout coughs, Grumpy Teapot runs hot (a fever), Dizzy Comet bumped its head.

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
	Case: string, -- CaseId: a Lv 1 case with no Room (Data/Cases)
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
		Case = "Cough",
		Wing = "Starter",
		UnlockStars = 0,
		Beats = {
			{ Emote = "🙈", Bubble = "Eek! Is it safe in there?" },
			{ Emote = "👀", Bubble = "I peeked inside. So cozy!" },
			{ Emote = "😷", Bubble = "Cough! You always help me." },
			{ Emote = "🌼", Bubble = "I told all my friends!" },
			{ Emote = "🥰", Bubble = "Can I be your mascot?" },
		},
		Reward = "SproutMascot",
		RewardKind = "Decor",
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
		Case = "Fever",
		Wing = "Starter",
		UnlockStars = 40,
		Beats = {
			{ Emote = "😤", Bubble = "Hmph. I'm too hot. Quickly." },
			{ Emote = "😒", Bubble = "Fine. That was... not awful." },
			{ Emote = "♨️", Bubble = "Phew! All steamy again. Hmph!" },
			{ Emote = "😊", Bubble = "Oops, I smiled. Don't tell!" },
			{ Emote = "🍀", Bubble = "Take my lucky kettle. Thanks!" },
		},
		Reward = "LuckyKettle",
		RewardKind = "Decor",
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
		Case = "BumpedHead",
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
