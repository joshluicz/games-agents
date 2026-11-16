--!strict
-- Time-played rewards (game/README.md "Play gifts, Doctor ranks, boosts and badges"). Lune-safe (no Roblox types).
-- Only ACTIVE play counts (Server/Playtime): at your own clinic, and not while you've been still for
-- Config.PlaytimeIdleSeconds. Everything here is earned in play: no Robux, nothing random.
--
-- Gifts: the daily play gifts, in order. Each unlocks after `Minutes` of active play on the current UTC day and is
-- opened by a tap (the ClaimPlayGift remote). A new UTC day refills them; after the last one there is nothing more to
-- chase today. No streaks: missing a day loses nothing.
--   Minutes  active play today to unlock it · Icon on its card · Cash, Stars on opening
--   Boost    a Data/Boosts id: a timed boost that also comes with it (extends, never stacks)
--
-- Ranks: lifetime active play (Data.Playtime.TotalSeconds) earns Doctor ranks, in order. Each rank gives once:
--   Decor    an exclusive Data/Decor item (EarnedBy = "Playtime")
--   Cash     a permanent Cash boost in percent while it's your rank (the highest one counts, they don't add up)
--   Id       also the key of its Roblox badge in Config.Badges (0 = not created yet, skipped)
-- Trainee is what the sign and the gifts panel show before the first rank.

export type Gift = { Minutes: number, Icon: string, Cash: number, Stars: number, Boost: string? }
export type Rank = { Id: string, Name: string, Icon: string, Hours: number, Decor: string, Cash: number }
export type Start = { Id: string, Name: string, Icon: string }

local GIFTS: { Gift } = {
	{ Minutes = 2, Icon = "🎁", Cash = 20, Stars = 0 },
	{ Minutes = 5, Icon = "🎁", Cash = 30, Stars = 1, Boost = "QuickHands" },
	{ Minutes = 10, Icon = "🎁", Cash = 50, Stars = 1 },
	{ Minutes = 15, Icon = "🎁", Cash = 60, Stars = 2, Boost = "LuckyTips" },
	{ Minutes = 25, Icon = "🎁", Cash = 100, Stars = 2 },
	{ Minutes = 40, Icon = "💝", Cash = 150, Stars = 3, Boost = "StarRush" },
}

local RANKS: { Rank } = {
	{ Id = "Intern", Name = "Intern", Icon = "🩹", Hours = 1, Decor = "InternRug", Cash = 2 },
	{ Id = "Resident", Name = "Resident", Icon = "🩺", Hours = 3, Decor = "ResidentFern", Cash = 4 },
	{ Id = "Doctor", Name = "Doctor", Icon = "🥼", Hours = 10, Decor = "DoctorLantern", Cash = 6 },
	{ Id = "SeniorDoctor", Name = "Senior Doctor", Icon = "🎖️", Hours = 25, Decor = "SeniorBench", Cash = 8 },
	{ Id = "Chief", Name = "Chief", Icon = "🌟", Hours = 50, Decor = "ChiefArch", Cash = 10 },
	{ Id = "Legend", Name = "Legend", Icon = "🏆", Hours = 100, Decor = "LegendStatue", Cash = 15 },
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
	Gifts = GIFTS,
	Ranks = RANKS,
	Trainee = { Id = "Trainee", Name = "Trainee", Icon = "🌱" } :: Start,
}) :: { Gifts: { Gift }, Ranks: { Rank }, Trainee: Start }
