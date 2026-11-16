--!strict
-- AilmentActing: how a waiting patient ACTS OUT what's wrong, with props, so you can see it at a glance. Joshua,
-- 2026-11-16: "they should have animations corresponding to their illness or need for attention. it should be visible
-- with perhaps props. but not gory".
-- Client/Feel/CreatureActing plays it on each client. The server only sets attributes on the patient (Ailment, State,
-- PatienceFraction), so nothing replicates per frame. Lune-safe (no Roblox types): colours are hex strings.
--
-- Acting (one per AilmentId in Data/Ailments; Default for anything else):
--   Motion   the body's beat, played every Every[1]..Every[2] seconds (Vocabulary.Motions)
--   Every    { min, max } seconds between beats; beats come sooner as patience runs low
--   Props    worn or held: client-only parts that pop off with a sparkle when the patient is treated (Vocabulary.Props)
--   Burst    particles on each beat (Vocabulary.Bursts), nil = none
--   Ambient  a soft, slow, continuous effect (Vocabulary.Ambients), nil = none
--   Face     the mouth on each beat (Vocabulary.Faces), nil = the usual sick "o"
--   Squint   the eyes squeeze shut on the beat
--   Cheeks   the colour the cheeks turn while ill (cold blue), nil = rosy as usual
--   Glow     a night creature's glow while ill, 0..1 of its usual (Lost glow dims it), nil = 1
--
-- Attention (every patient waiting in line): at PatienceFraction <= Wave it waves at you now and then; at <= Alert it
-- waves both arms, bounces, and a "!" pops up beside its head. Every motion honours the calm-effects setting.
-- Rated Minimal: cartoon care only (tissues, plasters, a scarf, honey). Nothing gross, scary or medical-needle-ish.

export type AilmentId = string
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

local ENTRIES: { [AilmentId]: Acting } = {
	-- Remedy Bench (Potion)
	Hiccups = { -- "hic!": a jolt and a hop, a bubble pops out; it holds a glass of water (it isn't working)
		Motion = "Hiccup",
		Every = { 1.6, 2.8 },
		Props = { "WaterGlass" },
		Burst = "Bubbles",
		Face = "Hic",
	},
	Sneezes = { -- winds up, tissue to the nose... achoo! A soft white puff
		Motion = "Sneeze",
		Every = { 3.5, 6 },
		Props = { "Tissue", "RedNose" },
		Burst = "Achoo",
		Face = "Achoo",
		Squint = true,
	},
	Cough = { -- a little mask; two or three small coughs, a paw over its mouth
		Motion = "Cough",
		Every = { 2.8, 4.5 },
		Props = { "Mask" },
		Burst = "CoughPuff",
		Squint = true,
	},
	-- Plaster Table (Plaster)
	Bump = { -- a plaster cross on a cartoon bump, stars circling its head, a slow dizzy sway
		Motion = "Dizzy",
		Every = { 4, 7 },
		Props = { "Bandage", "DizzyStars" },
		Face = "Ooh",
	},
	Scrape = { -- a plaster on its cheek, sniffles, a single tear, rubs the sore spot
		Motion = "Sniffle",
		Every = { 3, 5 },
		Props = { "CheekPlaster", "Tear" },
		Squint = true,
	},
	LostGlow = { -- its glow is dim and its tips go dull; it peeks into an empty jar and sighs
		Motion = "Droop",
		Every = { 4.5, 7 },
		Props = { "EmptyJar" },
		Burst = "Motes",
		Ambient = "Motes",
		Glow = 0.25,
	},
	-- Warm Bath (Bubbles)
	Sticky = { -- a honey blob on its head with slow drips; it tugs at its feet, stuck
		Motion = "Stuck",
		Every = { 3, 5 },
		Props = { "Honey" },
		Face = "Ooh",
	},
	Muddy = { -- mud spots; a quick wiggle shakes off a few drops
		Motion = "ShakeOff",
		Every = { 3.5, 5.5 },
		Props = { "MudSpots" },
		Burst = "Mud",
		Squint = true,
	},
	-- Cocoa Corner (Cocoa)
	Chills = { -- a cosy scarf, shivers, chattering teeth, little breath puffs, cold blue cheeks
		Motion = "Shiver",
		Every = { 1.8, 2.8 },
		Props = { "Scarf" },
		Burst = "Breath",
		Face = "Chatter",
		Cheeks = COLD_CHEEKS,
	},
	FrozenNose = { -- an ice cap on its nose and earmuffs; it cups its nose, then a "brrr" shake
		Motion = "NoseRub",
		Every = { 3, 5 },
		Props = { "IceNose", "Earmuffs" },
		Burst = "Frost",
		Ambient = "Snowflakes",
		Squint = true,
		Cheeks = COLD_CHEEKS,
	},
	-- Progression v2 (existing vocabulary only)
	Pollen = { -- a flower-dusted sneeze: tissue at the ready, achoo! with a soft puff
		Motion = "Sneeze",
		Every = { 3, 5.5 },
		Props = { "Tissue" },
		Burst = "Achoo",
		Face = "Achoo",
		Squint = true,
	},
	Prickles = { -- a plaster on a cartoon thorn; it tugs at it, stuck
		Motion = "Stuck",
		Every = { 3, 5 },
		Props = { "Bandage" },
		Face = "Ooh",
	},
	Airsick = { -- a dizzy sway with stars circling its head
		Motion = "Dizzy",
		Every = { 3.5, 6 },
		Props = { "DizzyStars" },
		Face = "Ooh",
	},
}

local ORDER = {
	"Hiccups",
	"Sneezes",
	"Cough",
	"Bump",
	"Scrape",
	"LostGlow",
	"Sticky",
	"Muddy",
	"Chills",
	"FrozenNose",
	"Pollen",
	"Prickles",
	"Airsick",
}

-- Anything without an entry (a new ailment, a kit model): a gentle sniffle, no props.
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
	Order: { AilmentId },
	Default: Acting,
	Attention: Attention,
	Vocabulary: { [string]: { string } },
	[AilmentId]: Acting,
}
return freeze(setmetatable(ENTRIES, {
	__index = {
		Order = freeze(ORDER),
		Default = freeze(DEFAULT),
		Attention = freeze(ATTENTION),
		Vocabulary = freeze(VOCABULARY),
	},
})) :: Module
