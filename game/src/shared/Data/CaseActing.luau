--!strict
-- CaseActing: how a patient ACTS OUT what's wrong, with props, so you can see it at a glance. Joshua, 2026-11-16:
-- "they should have animations corresponding to their illness or need for attention. it should be visible with
-- perhaps props. but not gory". The Real Clinic (build plan Task 3): keyed by CaseId (Data/Cases), the case a visit
-- rolled, where it used to be keyed by ailment.
-- Client/Feel/CreatureActing plays it on each client. The server only sets attributes on the patient (its case,
-- State, PatienceFraction), so nothing replicates per frame. Lune-safe (no Roblox types): colours are hex strings.
--
-- Acting (one per CaseId in Data/Cases; Default for anything else, such as a patient whose case isn't known yet):
--   Motion   the body's beat, played every Every[1]..Every[2] seconds (Vocabulary.Motions)
--   Every    { min, max } seconds between beats; beats come sooner as patience runs low
--   Props    worn or held: client-only parts that pop off with a sparkle when the patient is treated (Vocabulary.Props)
--   Burst    particles on each beat (Vocabulary.Bursts), nil = none
--   Ambient  a soft, slow, continuous effect (Vocabulary.Ambients), nil = none
--   Face     the mouth on each beat (Vocabulary.Faces), nil = the usual sick "o"
--   Squint   the eyes squeeze shut on the beat
--   Cheeks   the colour the cheeks turn while ill (cold blue, a warm flush), nil = rosy as usual
--   Glow     a night creature's glow while ill, 0..1 of its usual, nil = 1
-- Every case uses only the Vocabulary Feel/CreatureProps already draws, so nothing new needs drawing.
--
-- Attention (every patient waiting for you): at PatienceFraction <= Wave it waves at you now and then; at <= Alert
-- it waves both arms, bounces, and a "!" pops up beside its head. Every motion honours the calm-effects setting.
-- Rated Minimal (design §2): cartoon care only (tissues, a mask, a scarf, earmuffs, a glass of water). Nothing gross,
-- scary or medical-needle-ish, and no crying: the Vocabulary's Tear stays drawable but no case uses it.

export type CaseId = string
export type Acting = {
	Motion: string,
	Every: { number },
	Props: { string },
	Burst: string?,
	Ambient: string?,
	Face: string?,
	Squint: boolean?,
	Cheeks: string?,
	Glow: number?,
}
export type Attention = {
	Wave: number, -- PatienceFraction at or below this: a wave now and then
	Alert: number, -- at or below this: both arms, a bounce and the "!"
	WaveEvery: { number }, -- { min, max } seconds between waves
	AlertEvery: { number },
}

local COLD_CHEEKS = "#9FD4FF" -- a soft icy blue
local WARM_CHEEKS = "#FF9C8A" -- a warm flush
local ITCHY_CHEEKS = "#FF7FA8" -- pink and itchy

local ENTRIES: { [CaseId]: Acting } = {
	-- Lv 1
	Cough = { -- a little mask; two or three small coughs, a paw over its mouth
		Motion = "Cough",
		Every = { 2.8, 4.5 },
		Props = { "Mask" },
		Burst = "CoughPuff",
		Squint = true,
	},
	Fever = { -- warm cheeks and a glass of water; it droops and sighs
		Motion = "Droop",
		Every = { 4, 6.5 },
		Props = { "WaterGlass" },
		Face = "Ooh",
		Cheeks = WARM_CHEEKS,
	},
	CutKnee = { -- sniffles, a tissue at the ready, and rubs the sore spot
		Motion = "Sniffle",
		Every = { 3, 5 },
		Props = { "Tissue" },
		Squint = true,
	},
	BumpedHead = { -- stars circling its head, a slow dizzy sway
		Motion = "Dizzy",
		Every = { 4, 7 },
		Props = { "DizzyStars" },
		Face = "Ooh",
	},
	Earache = { -- earmuffs on, a sniffle and a squint
		Motion = "Sniffle",
		Every = { 3.5, 5.5 },
		Props = { "Earmuffs" },
		Face = "Ooh",
		Squint = true,
	},
	-- Lv 2
	Sprain = { -- it tugs at its foot, stuck: it can't walk on it
		Motion = "Stuck",
		Every = { 3, 5 },
		Props = { "Tissue" },
		Face = "Ooh",
	},
	SoreThroat = { -- a cosy scarf round its throat, and small coughs
		Motion = "Cough",
		Every = { 3, 5 },
		Props = { "Scarf" },
		Burst = "CoughPuff",
	},
	Rash = { -- pink cheeks and a red nose; an itchy little wiggle
		Motion = "ShakeOff",
		Every = { 2.5, 4 },
		Props = { "RedNose" },
		Squint = true,
		Cheeks = ITCHY_CHEEKS,
	},
	-- Lv 3
	BrokenArm = { -- it droops and holds its arm still, a tissue in the other paw
		Motion = "Droop",
		Every = { 4, 6.5 },
		Props = { "Tissue" },
		Face = "Ooh",
	},
	-- Bought rooms
	SoreMuscles = { -- achy: a slow droop and a sigh, a glass of water
		Motion = "Droop",
		Every = { 4.5, 7 },
		Props = { "WaterGlass" },
		Squint = true,
	},
	Chills = { -- a cosy scarf, shivers, chattering teeth, little breath puffs, cold blue cheeks
		Motion = "Shiver",
		Every = { 1.8, 2.8 },
		Props = { "Scarf" },
		Burst = "Breath",
		Face = "Chatter",
		Cheeks = COLD_CHEEKS,
	},
	-- Lv 5, by air ambulance
	BrokenLeg = { -- stars circling its head from the flight, and stuck on one leg
		Motion = "Stuck",
		Every = { 3.5, 6 },
		Props = { "DizzyStars" },
		Face = "Ooh",
	},
}

local ORDER = {
	"Cough",
	"Fever",
	"CutKnee",
	"BumpedHead",
	"Earache",
	"Sprain",
	"SoreThroat",
	"Rash",
	"BrokenArm",
	"SoreMuscles",
	"Chills",
	"BrokenLeg",
}

-- Anything without an entry (a case not known yet, a new case, a kit model): a gentle sniffle, no props.
local DEFAULT: Acting = { Motion = "Sniffle", Every = { 3.5, 5.5 }, Props = {}, Squint = true }

local ATTENTION: Attention = {
	Wave = 0.5,
	Alert = 0.25,
	WaveEvery = { 4.5, 6.5 },
	AlertEvery = { 2.2, 3.2 },
}

-- Everything CreatureActing knows how to play. Specs check every entry uses only these.
local VOCABULARY = {
	Motions = { "Hiccup", "Sneeze", "Cough", "Dizzy", "Sniffle", "Droop", "Stuck", "ShakeOff", "Shiver", "NoseRub" },
	Props = {
		"WaterGlass",
		"Tissue",
		"RedNose",
		"Mask",
		"Bandage",
		"DizzyStars",
		"CheekPlaster",
		"Tear",
		"EmptyJar",
		"Honey",
		"MudSpots",
		"Scarf",
		"IceNose",
		"Earmuffs",
	},
	Bursts = { "Bubbles", "Achoo", "CoughPuff", "Motes", "Mud", "Breath", "Frost" },
	Ambients = { "Motes", "Snowflakes" },
	Faces = { "Hic", "Achoo", "Ooh", "Chatter" },
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = {
	Order: { CaseId },
	Default: Acting,
	Attention: Attention,
	Vocabulary: { [string]: { string } },
	[CaseId]: Acting,
}
return freeze(setmetatable(ENTRIES, {
	__index = {
		Order = freeze(ORDER),
		Default = freeze(DEFAULT),
		Attention = freeze(ATTENTION),
		Vocabulary = freeze(VOCABULARY),
	},
})) :: Module
