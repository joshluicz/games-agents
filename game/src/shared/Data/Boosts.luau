--!strict
-- Timed boosts (game/README.md "Boosts"). Lune-safe (no Roblox types). Earned in play only (the daily play gifts in
-- Data/Playtime); never sold, never random.
--   Name, Icon   what the HUD chip and the panels show
--   Kind         "Cash" | "Stars" | "MakeSpeed" | "Patience" | "Tips" (Logic/Boosts)
--   Percent      how much stronger while it runs: MakeSpeed +25% = hold time / 1.25; Stars +100% = x2
--   Minutes      how long one gift of it lasts
-- A timed boost only ticks while you're actually playing (the same active seconds as Data.Playtime), so leaving the
-- game never wastes it. Getting the same boost again EXTENDS it (up to Config.BoostMaxMinutes), never stacks it.

export type BoostId = string
export type Boost = { Name: string, Icon: string, Kind: string, Percent: number, Minutes: number }

local ENTRIES: { [BoostId]: Boost } = {
	QuickHands = { Name = "Quick Hands", Icon = "⚡", Kind = "MakeSpeed", Percent = 25, Minutes = 10 },
	LuckyTips = { Name = "Lucky Tips", Icon = "🍀", Kind = "Tips", Percent = 50, Minutes = 15 },
	StarRush = { Name = "Star Rush", Icon = "🌠", Kind = "Stars", Percent = 100, Minutes = 10 },
}

local ORDER = { "QuickHands", "LuckyTips", "StarRush" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { BoostId }, [BoostId]: Boost }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
