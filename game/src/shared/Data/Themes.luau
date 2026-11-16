--!strict
-- Branch themes: a cosmetic skin for the hospital building (Progression v2 build plan §B5; memory-20261116-019 item
-- 6). Lune-safe (hex strings). A rebirth switches you to the newest theme unlocked; you can pick any unlocked one
-- later (SetTheme). Themes recolour the building's walls, roof and trim and add one small roof prop (<= 6 parts,
-- PlotBuilder). The plot's own accent colour never changes: kids find "the pink one". Names are placeholders
-- (OPEN #1). Iterate `Themes.Order` (by Rebirths).
--
--   Name, Icon   the Branch panel's theme card
--   Rebirths     the rebirths that unlock it (0 = from the start)
--   Wall, Roof, Trim   hex colours; "" = the building's own candy colours (Candy: today's look, no recolour)
--   Prop         the roof prop PlotBuilder adds ("" = none)

export type ThemeId = string
export type Theme = {
	Name: string,
	Icon: string,
	Rebirths: number,
	Wall: string,
	Roof: string,
	Trim: string,
	Prop: string,
}

local ENTRIES: { [ThemeId]: Theme } = {
	Candy = { Name = "Candy", Icon = "🍬", Rebirths = 0, Wall = "", Roof = "", Trim = "", Prop = "" },
	Arctic = {
		Name = "Arctic",
		Icon = "❄️",
		Rebirths = 1,
		Wall = "#EAF6FF",
		Roof = "#7FC8FF",
		Trim = "#FFFFFF",
		Prop = "Icicles",
	},
	Jungle = {
		Name = "Jungle",
		Icon = "🌴",
		Rebirths = 2,
		Wall = "#CFF5C0",
		Roof = "#3DBE5A",
		Trim = "#FFE07A",
		Prop = "Palm",
	},
	Space = {
		Name = "Space",
		Icon = "🚀",
		Rebirths = 3,
		Wall = "#D9D2FF",
		Roof = "#5B4BD6",
		Trim = "#FFD84A",
		Prop = "Rocket",
	},
	Ocean = {
		Name = "Ocean",
		Icon = "🐚",
		Rebirths = 4,
		Wall = "#C8F4F0",
		Roof = "#26B5C9",
		Trim = "#FFB3C7",
		Prop = "Shell",
	},
	Royal = {
		Name = "Royal",
		Icon = "👑",
		Rebirths = 5,
		Wall = "#FFF4D6",
		Roof = "#F2B705",
		Trim = "#B04CFF",
		Prop = "Crown",
	},
}

local ORDER = { "Candy", "Arctic", "Jungle", "Space", "Ocean", "Royal" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { ThemeId }, Default: ThemeId, [ThemeId]: Theme }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER), Default = "Candy" } })) :: Module
