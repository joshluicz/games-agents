--!strict
-- Achievement badges, in tiers (game/README.md "Badges"). Lune-safe (no Roblox types). List-driven: a new badge is a
-- new row here (and, for a new counter, one Server/Badges.add call where it happens). Nothing is paid or random.
--
-- Tiers: the six tiers, lowest first. Reaching a tier pays its Cash and Stars once, and the badge's Boost grows.
--   Color  the tier's frame colour (hex) in the Badge Book
--
-- Categories: the Badge Book's tabs, in order.
--
-- List: every badge, in Book order.
--   Stat        what it counts. A Data.Stats counter ("Cures", "NightCures", "Visitors", "Friendly",
--               "Cures:<WingId>", "Made:<StationId>"), or one worked out from the save (Logic/Badges.DERIVED):
--               "PlayHours" (Data.Playtime.TotalSeconds in whole hours), "Beats" (story beats told, all regulars),
--               "Builder" (rooms bought + decor owned)
--   Goal        what to do, 6 words or fewer (the card's subtitle)
--   Thresholds  the Stat value for each tier (6 numbers, rising)
--   Boost       a permanent boost per tier reached: { Kind, Scope?, Percent }. Kind as in Logic/Boosts; Scope limits it
--               to a wing ("Starter"...), a station ("Remedy"...) or "Night" cures. Gold (tier 3) of a 1% badge = +3%.
-- Room left for later badges (perfect mini-games, nurses hired, hospital level): add a counter and a row.

export type Tier = { Id: string, Name: string, Icon: string, Color: string, Cash: number, Stars: number }
export type Category = { Id: string, Name: string, Icon: string }
export type Boost = { Kind: string, Scope: string?, Percent: number }
export type Badge = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,
	Stat: string,
	Goal: string,
	Thresholds: { number },
	Boost: Boost,
}

local TIERS: { Tier } = {
	{ Id = "Bronze", Name = "Bronze", Icon = "🥉", Color = "#D9893F", Cash = 50, Stars = 2 },
	{ Id = "Silver", Name = "Silver", Icon = "🥈", Color = "#B8C4D9", Cash = 150, Stars = 4 },
	{ Id = "Gold", Name = "Gold", Icon = "🥇", Color = "#FFC628", Cash = 400, Stars = 8 },
	{ Id = "Diamond", Name = "Diamond", Icon = "💎", Color = "#45D6FF", Cash = 1000, Stars = 15 },
	{ Id = "Ruby", Name = "Ruby", Icon = "♦️", Color = "#FF2E63", Cash = 2500, Stars = 25 },
	{ Id = "Mythic", Name = "Mythic", Icon = "🔮", Color = "#A64DFF", Cash = 6000, Stars = 40 },
}

local CATEGORIES: { Category } = {
	{ Id = "Clinic", Name = "Clinic", Icon = "🏥" },
	{ Id = "Wings", Name = "Wings", Icon = "🗺️" },
	{ Id = "Stations", Name = "Stations", Icon = "🧪" },
	{ Id = "Friends", Name = "Friends", Icon = "💛" },
}

local BIG = { 25, 100, 500, 2000, 10000, 50000 }
local WING = { 10, 50, 200, 750, 3000, 12000 }
local SMALL_WING = { 5, 25, 100, 400, 1500, 6000 }
local MAKE = { 25, 100, 400, 1500, 6000, 25000 }
local SMALL_MAKE = { 10, 50, 200, 800, 3000, 12000 }

local LIST: { Badge } = {
	-- Clinic
	{
		Id = "Healer",
		Name = "Healer",
		Icon = "🏥",
		Category = "Clinic",
		Stat = "Cures",
		Goal = "Cure patients",
		Thresholds = BIG,
		Boost = { Kind = "Cash", Percent = 1 },
	},
	{
		Id = "NightShift",
		Name = "Night Shift",
		Icon = "🔦",
		Category = "Clinic",
		Stat = "NightCures",
		Goal = "Cure patients at night",
		Thresholds = SMALL_WING,
		Boost = { Kind = "Cash", Scope = "Night", Percent = 5 },
	},
	{
		Id = "Visitor",
		Name = "Visitor",
		Icon = "⭐",
		Category = "Clinic",
		Stat = "Visitors",
		Goal = "Cure Today's Visitor",
		Thresholds = { 1, 5, 15, 40, 100, 250 },
		Boost = { Kind = "Patience", Percent = 4 },
	},
	{
		Id = "Builder",
		Name = "Builder",
		Icon = "🏠",
		Category = "Clinic",
		Stat = "Builder",
		Goal = "Buy rooms and decor",
		Thresholds = { 1, 3, 6, 10, 16, 22 },
		Boost = { Kind = "Tips", Percent = 4 },
	},
	{
		Id = "Dedication",
		Name = "Dedication",
		Icon = "⏱️",
		Category = "Clinic",
		Stat = "PlayHours",
		Goal = "Hours of play",
		Thresholds = { 1, 5, 15, 40, 100, 250 },
		Boost = { Kind = "MakeSpeed", Percent = 2 },
	},
	-- Wings: cures of that wing's creatures
	{
		Id = "Meadow",
		Name = "Meadow",
		Icon = "🌳",
		Category = "Wings",
		Stat = "Cures:Starter",
		Goal = "Cure Meadow patients",
		Thresholds = WING,
		Boost = { Kind = "Cash", Scope = "Starter", Percent = 2 },
	},
	{
		Id = "BubblePond",
		Name = "Bubble Pond",
		Icon = "🛁",
		Category = "Wings",
		Stat = "Cures:Bath",
		Goal = "Cure Bubble Pond patients",
		Thresholds = { 10, 40, 150, 600, 2500, 10000 },
		Boost = { Kind = "Cash", Scope = "Bath", Percent = 2 },
	},
	{
		Id = "SnowyHills",
		Name = "Snowy Hills",
		Icon = "❄️",
		Category = "Wings",
		Stat = "Cures:Winter",
		Goal = "Cure Snowy Hills patients",
		Thresholds = SMALL_WING,
		Boost = { Kind = "Cash", Scope = "Winter", Percent = 2 },
	},
	{
		Id = "MoonlitWoods",
		Name = "Moonlit Woods",
		Icon = "🌙",
		Category = "Wings",
		Stat = "Cures:Night",
		Goal = "Cure Moonlit Woods patients",
		Thresholds = SMALL_WING,
		Boost = { Kind = "Cash", Scope = "Night", Percent = 2 },
	},
	-- Stations: treatments made there
	{
		Id = "Potions",
		Name = "Potions",
		Icon = "🧪",
		Category = "Stations",
		Stat = "Made:Remedy",
		Goal = "Make potions",
		Thresholds = MAKE,
		Boost = { Kind = "MakeSpeed", Scope = "Remedy", Percent = 3 },
	},
	{
		Id = "Plasters",
		Name = "Plasters",
		Icon = "🩹",
		Category = "Stations",
		Stat = "Made:Plaster",
		Goal = "Make plasters",
		Thresholds = MAKE,
		Boost = { Kind = "MakeSpeed", Scope = "Plaster", Percent = 3 },
	},
	{
		Id = "Bubbles",
		Name = "Bubbles",
		Icon = "🧼",
		Category = "Stations",
		Stat = "Made:Bath",
		Goal = "Run warm baths",
		Thresholds = SMALL_MAKE,
		Boost = { Kind = "MakeSpeed", Scope = "Bath", Percent = 3 },
	},
	{
		Id = "Cocoa",
		Name = "Cocoa",
		Icon = "☕",
		Category = "Stations",
		Stat = "Made:Cocoa",
		Goal = "Make hot cocoa",
		Thresholds = { 10, 40, 150, 600, 2500, 10000 },
		Boost = { Kind = "MakeSpeed", Scope = "Cocoa", Percent = 3 },
	},
	-- Friends
	{
		Id = "Storyteller",
		Name = "Storyteller",
		Icon = "💬",
		Category = "Friends",
		Stat = "Beats",
		Goal = "Hear your regulars' stories",
		Thresholds = { 1, 3, 6, 9, 12, 15 },
		Boost = { Kind = "Tips", Percent = 3 },
	},
	{
		Id = "Friendly",
		Name = "Friendly",
		Icon = "❤️",
		Category = "Friends",
		Stat = "Friendly",
		Goal = "Send hearts, help friends",
		Thresholds = { 1, 5, 20, 60, 150, 400 },
		Boost = { Kind = "Patience", Percent = 3 },
	},
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

return freeze({
	Tiers = TIERS,
	Categories = CATEGORIES,
	List = LIST,
}) :: { Tiers: { Tier }, Categories: { Category }, List: { Badge } }
