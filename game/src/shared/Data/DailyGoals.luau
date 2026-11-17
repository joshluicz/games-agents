--!strict
-- Daily goals: one new goal is granted per UTC day, banked up to Config.MaxBankedGoals. They never expire and
-- there are no streaks (build plan §B2, design §5.5). An ARRAY (the pool): find a goal by its Id.
-- Lune-safe (no Roblox types).
--
-- Kind  "Cure"      treat Target patients (any)
--       "CureNight" treat Target night patients
--       "Make"      take Target supplies or dispense Target medicines, at any station
--       "CureWing"  treat Target patients from Wing (only offer it if the player can treat that wing)
-- The Kind and Id names are saved ids from before the Real Clinic: they keep "Cure", but players only ever read
-- "treat" (design §12; the Mailbox words them). A goal whose Id leaves this pool is pruned from saves on load
-- (Logic/Daily.prune), so no banked goal can name something that's gone.

export type GoalKind = "Cure" | "CureNight" | "Make" | "CureWing"
export type GoalDef = {
	Id: string,
	Kind: GoalKind,
	Target: number,
	Wing: string?, -- WingId, for CureWing
	Icon: string,
	Reward: { Cash: number, Stars: number },
}

local POOL: { GoalDef } = {
	{ Id = "Cure5", Kind = "Cure", Target = 5, Icon = "😊", Reward = { Cash = 40, Stars = 2 } },
	{ Id = "Cure12", Kind = "Cure", Target = 12, Icon = "🥳", Reward = { Cash = 90, Stars = 4 } },
	{ Id = "Make10", Kind = "Make", Target = 10, Icon = "✨", Reward = { Cash = 40, Stars = 2 } },
	{ Id = "Make20", Kind = "Make", Target = 20, Icon = "🌟", Reward = { Cash = 80, Stars = 3 } },
	{ Id = "Night3", Kind = "CureNight", Target = 3, Icon = "🌙", Reward = { Cash = 60, Stars = 3 } },
	{
		Id = "Meadow6",
		Kind = "CureWing",
		Target = 6,
		Wing = "Starter",
		Icon = "🌳",
		Reward = { Cash = 50, Stars = 2 },
	},
	{ Id = "Bath4", Kind = "CureWing", Target = 4, Wing = "Bath", Icon = "🛁", Reward = { Cash = 70, Stars = 3 } },
	{
		Id = "Snow4",
		Kind = "CureWing",
		Target = 4,
		Wing = "Winter",
		Icon = "❄️",
		Reward = { Cash = 80, Stars = 3 },
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

return freeze(POOL) :: { GoalDef }
