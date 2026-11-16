--!strict
-- Perk cards (Progression v2 build plan §B5; design §8 "Rebirth features", memory-20261116-019). Lune-safe.
-- Each rebirth offers 3 random cards you don't own yet ("3 random cards, never repeats": every card is equally
-- likely, and the screen says so); you keep the one you choose forever. Once all 12 are owned the offer is the
-- Fallback card, which never runs out. Iterate `Perks.Order`; `for id, perk in Perks` yields only the 12.
--
--   Name, Icon   the card
--   Text         what it does, 6 words or fewer
--   Kind         what it changes (Logic/Rebirth.effects merges it with the tree):
--                "Arrive"     spawn seconds x Value (the line still caps at 3)
--                "StartRoom"  every branch starts owning the room "BathRoom" (applied by Logic/Rebirth.apply)
--                "XP"         nurse XP x Value
--                "NightOwl"   night patients keep coming for Config.NightOwl of a night after morning (§E4)
--                "Tray"       +Value carry (Carry.capacity)
--                "BeltScout"  the belt shows you the next arrival's rarity
--                "StartCash"  cash after a rebirth = Value
--                "StartUpgrades"  every branch starts with Faster Hands 2 and Tip Jar 1 (Logic/Rebirth.WARM_UP)
--                "SirenPro"   the A&E interval / Value
--                "Patience"   +Value percent patience (the branch boost source, Config.BranchCaps)
--                "StartLevel" every branch starts at hospital Lv Value
--                "Recharge"   every ability cooldown x Value
--                "Points"     +Value Branch Ability Tree points (the Fallback card)
--   Value        the number for its Kind (1 for the flags)
-- The start-of-branch cards (StartRoom, StartCash, StartUpgrades, StartLevel) also apply once when chosen, since you
-- choose at the start of a branch.

export type PerkId = string
export type Perk = { Name: string, Icon: string, Text: string, Kind: string, Value: number }

local ENTRIES: { [PerkId]: Perk } = {
	BusyDoors = { Name = "Busy Doors", Icon = "🚪", Text = "Patients come 15% faster", Kind = "Arrive", Value = 0.85 },
	BathReady = { Name = "Bath Ready", Icon = "🛁", Text = "Start with the Bath Room", Kind = "StartRoom", Value = 1 },
	FastLearners = {
		Name = "Fast Learners",
		Icon = "📚",
		Text = "Nurses learn twice as fast",
		Kind = "XP",
		Value = 2,
	},
	NightOwl = { Name = "Night Owl", Icon = "🦉", Text = "Night patients stay longer", Kind = "NightOwl", Value = 1 },
	BigHands = { Name = "Big Hands", Icon = "🧺", Text = "Carry one more", Kind = "Tray", Value = 1 },
	BeltScout = { Name = "Belt Scout", Icon = "🔭", Text = "See the next belt nurse", Kind = "BeltScout", Value = 1 },
	SeedMoney = {
		Name = "Seed Money",
		Icon = "💰",
		Text = "Start branches with 💰1,000",
		Kind = "StartCash",
		Value = 1000,
	},
	WarmUp = { Name = "Warm Up", Icon = "⚡", Text = "Start with two upgrades", Kind = "StartUpgrades", Value = 1 },
	SirenPro = { Name = "Siren Pro", Icon = "🚑", Text = "Ambulances come 25% more", Kind = "SirenPro", Value = 1.25 },
	PatientPals = {
		Name = "Patient Pals",
		Icon = "💺",
		Text = "Patients wait 20% longer",
		Kind = "Patience",
		Value = 20,
	},
	ClinicStart = {
		Name = "Clinic Start",
		Icon = "🏠",
		Text = "Start at hospital Lv 2",
		Kind = "StartLevel",
		Value = 2,
	},
	SecondWind = {
		Name = "Second Wind",
		Icon = "🔁",
		Text = "Abilities recharge 20% faster",
		Kind = "Recharge",
		Value = 0.8,
	},
}

local ORDER = {
	"BusyDoors",
	"BathReady",
	"FastLearners",
	"NightOwl",
	"BigHands",
	"BeltScout",
	"SeedMoney",
	"WarmUp",
	"SirenPro",
	"PatientPals",
	"ClinicStart",
	"SecondWind",
}

-- The card once all 12 are owned. Its id is "TreePoints"; it is never stored in Rebirth.Perks.
local FALLBACK: Perk = { Name = "Tree Points", Icon = "🌳", Text = "+2 tree points", Kind = "Points", Value = 2 }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { PerkId }, Fallback: Perk, FallbackId: PerkId, [PerkId]: Perk }
return freeze(setmetatable(ENTRIES, {
	__index = { Order = freeze(ORDER), Fallback = freeze(FALLBACK), FallbackId = "TreePoints" },
})) :: Module
