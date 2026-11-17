--!strict
-- Wings: groups of patients for the Patient Book. Completing a wing's set (every patient treated at least once)
-- grants its SetReward decor (build plan Task 4). Lune-safe (no Roblox types).
-- The Real Clinic (design §15 #2): each wing also has a case pool (Data/Cases.POOLS, keyed by these ids), so a
-- patient's case is rolled each visit from its wing's pool.
-- Progression v2 (build plan §B5): a wing may need rebirths (Rebirths) and may come only by helicopter (Only =
-- "Helicopter"). Sunny's patients come from the start of each branch after R1, with whatever stations you have; Sky's
-- only on the R2 air ambulance. Their patients never come (nor as Today's Visitor) before that.

export type WingId = string
export type Wing = {
	Name: string,
	Icon: string,
	SetReward: string, -- DecorId granted when the wing's Book set completes
	Rebirths: number?, -- the rebirths an owner needs before its patients come (nil = 0)
	Only: string?, -- "Helicopter": its patients come only by air ambulance
}

local ENTRIES: { [WingId]: Wing } = {
	Starter = { Name = "Meadow", Icon = "🌳", SetReward = "HeartRug" },
	Bath = { Name = "Bubble Pond", Icon = "🛁", SetReward = "RubberDuckFountain" },
	Winter = { Name = "Snowy Hills", Icon = "❄️", SetReward = "SnowGlobeLamp" },
	Night = { Name = "Moonlit Woods", Icon = "🌙", SetReward = "MoonLantern" },
	-- Progression v2 (placeholder names, OPEN #1)
	Sunny = { Name = "Sunny Fields", Icon = "🌻", SetReward = "SunflowerArch", Rebirths = 1 },
	Sky = { Name = "Sky Harbour", Icon = "🚁", SetReward = "CloudSwing", Rebirths = 2, Only = "Helicopter" },
}

local ORDER = { "Starter", "Bath", "Winter", "Night", "Sunny", "Sky" }

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
