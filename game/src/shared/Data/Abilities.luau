--!strict
-- Nurse signature abilities (Progression v2 build plan §B5; design §7, memory-20261116-017). Lune-safe.
-- Every ability fires BY ITSELF when it would help (build plan §E3: no button to learn); a "banked" one lights up
-- when it's ready and is spent by the next matching treatment or treated patient (its cooldown starts then). Cooldowns
-- show as a filling ring, never as seconds (red line 3). Iterate `Abilities.Order`.
--
--   Name, Icon   the nurse card and the sparkle chip
--   Kind         what it does (Logic/Abilities.useful says when it helps; Server/Abilities and Patients do it):
--                "AutoPerfect"  banked: the next Value mini-games (of Game, or any game when Game is nil) are PERFECT
--                "TrayItem"     puts Value items the line needs into the nurse tray
--                "RefillFront"  the front waiting patient's patience refills
--                "PauseLine"    every waiting patient's patience pauses for Value seconds
--                "FastMake"     station holds x0.5 for Value seconds
--                "CashNext"     banked: the next Value patients treated at this plot pay x2
--                "StarsNext"    banked: the next patient treated gives +Value ⭐
--                "RefillLine"   every waiting patient's patience refills
--                "InstantMake"  station holds take the shortest time for Value seconds
--                "CureLine"     every waiting patient (not being treated) is treated on the spot: the whole visit,
--                               medicine included (abilities are rare and earned; design §15 #1). The Kind keeps its
--                               old id
--                "Recharge"     every OTHER ability at this plot is ready now
--   Cooldown     seconds after it fires (x0.85 at nurse Lv 5 and again at Lv 10, never under
--                Config.Abilities.MinCooldown; x0.8 with the SecondWind perk)
--   Daily        true: once per in-game day instead (an IsNight true -> false edge); Cooldown is then only the ring's
--                length and never scales
--   Values       { base, from Lv 5, from Lv 10 } (games, items, seconds, patients or ⭐; 1 for the ones without a value)
--   Game         the mini-game an AutoPerfect works on, a GameId (Logic/MiniGame.ENGINE; nil = any): Quick Plaster the
--                🩹 Plaster game, Quick Soap the 🛁 Bath game (they were the Patch and Scrub engines before the Real
--                Clinic). Ids are kept, so saved nurses keep their ability

export type AbilityId = string
export type Ability = {
	Name: string,
	Icon: string,
	Kind: string,
	Cooldown: number,
	Daily: boolean?,
	Values: { number },
	Game: string?,
}

local ENTRIES: { [AbilityId]: Ability } = {
	QuickBandage = {
		Name = "Quick Plaster",
		Icon = "🩹",
		Kind = "AutoPerfect",
		Cooldown = 60,
		Values = { 1, 2, 3 },
		Game = "Plaster",
	},
	QuickSoap = {
		Name = "Quick Soap",
		Icon = "🧼",
		Kind = "AutoPerfect",
		Cooldown = 60,
		Values = { 1, 2, 3 },
		Game = "Bath",
	},
	FreshBrew = { Name = "Fresh Supplies", Icon = "📦", Kind = "TrayItem", Cooldown = 75, Values = { 1, 2, 3 } },
	WarmHug = { Name = "Warm Hug", Icon = "🤗", Kind = "RefillFront", Cooldown = 60, Values = { 1, 1, 1 } },
	CalmSong = { Name = "Calm Song", Icon = "🎵", Kind = "PauseLine", Cooldown = 90, Values = { 10, 13, 16 } },
	BusyPaws = { Name = "Busy Paws", Icon = "⚡", Kind = "FastMake", Cooldown = 90, Values = { 10, 13, 16 } },
	DoubleDose = { Name = "Double Dose", Icon = "💊", Kind = "CashNext", Cooldown = 120, Values = { 1, 2, 3 } },
	StarBurst = { Name = "Star Burst", Icon = "🌟", Kind = "StarsNext", Cooldown = 120, Values = { 3, 4, 5 } },
	GoldenTouch = { Name = "Golden Touch", Icon = "✨", Kind = "AutoPerfect", Cooldown = 150, Values = { 3, 4, 5 } },
	RainbowCheer = { Name = "Rainbow Cheer", Icon = "🌈", Kind = "RefillLine", Cooldown = 150, Values = { 1, 1, 1 } },
	TimeBubble = { Name = "Time Bubble", Icon = "⏳", Kind = "InstantMake", Cooldown = 180, Values = { 8, 10, 12 } },
	Miracle = { Name = "Miracle", Icon = "💫", Kind = "CureLine", Cooldown = 600, Daily = true, Values = { 1, 1, 1 } },
	TeamSpirit = { Name = "Team Spirit", Icon = "🏢", Kind = "Recharge", Cooldown = 240, Values = { 1, 1, 1 } },
}

local ORDER = {
	"QuickBandage",
	"QuickSoap",
	"FreshBrew",
	"WarmHug",
	"CalmSong",
	"BusyPaws",
	"DoubleDose",
	"StarBurst",
	"GoldenTouch",
	"RainbowCheer",
	"TimeBubble",
	"Miracle",
	"TeamSpirit",
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { AbilityId }, [AbilityId]: Ability }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
