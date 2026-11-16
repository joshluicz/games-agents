--!strict
-- Wings: groups of patients for the Patient Book. Completing a wing's set (every patient cured at least once)
-- grants its SetReward decor (build plan Task 4). Lune-safe (no Roblox types).

export type WingId = string
export type Wing = {
	Name: string,
	Icon: string,
	SetReward: string, -- DecorId granted when the wing's Book set completes
}

local ENTRIES: { [WingId]: Wing } = {
	Starter = { Name = "Meadow", Icon = "🌳", SetReward = "HeartRug" },
	Bath = { Name = "Bubble Pond", Icon = "🛁", SetReward = "RubberDuckFountain" },
	Winter = { Name = "Snowy Hills", Icon = "❄️", SetReward = "SnowGlobeLamp" },
	Night = { Name = "Moonlit Woods", Icon = "🌙", SetReward = "MoonLantern" },
}

local ORDER = { "Starter", "Bath", "Winter", "Night" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { WingId }, [WingId]: Wing }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
