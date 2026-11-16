--!strict
-- What one cure pays (build plan §B6). Pure: no Roblox services, no requires, so Lune can test it.
--   Pay.reward(args): { Cash: number, Stars: number }
--
-- Cash = BasePay
--      x (1 + RecipeItemBonus x (Items - 1))    a longer recipe pays more: +50% for each item after the first
--      x (1 + QuickServeBonus x PatienceLeft)   cure while they still have patience: up to +50%
--      x (1 + TipsPerLevel x Tips)              the clinic's Tip Jar level: +20% each
--      x Cheer                                  the plot's Cheerer on duty (CheerTip, 1 = none; at most x3)
--      x NightPayMultiplier                     night patients
--      x SparklyMultiplier / FrostyMultiplier   a rare variant
--      x VisitorMultiplier                      Today's Visitor
--      x CashBoost                              Logic/Boosts: the helper's Cash boosts (1 = none)
-- where the Tip Jar factor also takes TipsBoost (the helper's Tips boosts, as a fraction: 0.5 = +50%) on top, so a
-- Tips boost works without a Tip Jar too. Rounded to a whole number, and never below 1.
-- Stars = 3 for a regular or Today's Visitor, 2 at night, otherwise 1. The best reason wins; they don't add up.
-- Then x StarsBoost (the owner's Stars boosts, 1 = none), rounded, never below the unboosted stars.
--
-- Every input is untrusted: a junk number falls back to its neutral value (patience 0, tips 0) and a missing
-- Cfg field counts as "no bonus", so a bad call pays a little instead of erroring mid-cure.

export type Cfg = {
	RecipeItemBonus: number?,
	QuickServeBonus: number?,
	TipsPerLevel: number?,
	NightPayMultiplier: number?,
	SparklyMultiplier: number?,
	FrostyMultiplier: number?,
	VisitorMultiplier: number?,
}

export type RewardArgs = {
	BasePay: number,
	Tips: number, -- Tip Jar level of the clinic
	PatienceLeft: number, -- 0..1
	Night: boolean,
	Variant: string?, -- VariantId: "Sparkly" | "Frosty"
	Visitor: boolean,
	Regular: boolean,
	Items: number?, -- the patient's recipe length (1..MAX_ITEMS; nil = 1)
	Cheer: number?, -- the plot's Cheerer tip multiplier (nil or below 1 = none)
	Cfg: Cfg, -- Shared/Config
	CashBoost: number?, -- a multiplier >= 1 (Server/Boosts); nil or junk = 1
	TipsBoost: number?, -- a fraction >= 0 added to the Tip Jar factor; nil or junk = 0
	StarsBoost: number?, -- a multiplier >= 1; nil or junk = 1
}

export type Reward = { Cash: number, Stars: number }

local Pay = {}

Pay.STARS_DAY = 1
Pay.STARS_NIGHT = 2
Pay.STARS_SPECIAL = 3 -- a regular or Today's Visitor
Pay.MAX_ITEMS = 3 -- recipes are 1..3 items (Logic/Recipe.MAX)
Pay.MAX_CHEER = 3 -- a sanity cap on the Cheerer multiplier (Cheerers give at most ~1.4)

-- VariantId -> the Config field holding its cash multiplier.
local VARIANT_MULTIPLIER: { [string]: string } = {
	Sparkly = "SparklyMultiplier",
	Frosty = "FrostyMultiplier",
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function numberOr(value: any, fallback: number): number
	return if finite(value) then value else fallback
end

-- A multiplier from Cfg: a finite number above 0, or 1 (no change).
local function multiplier(cfg: any, key: string): number
	local value = if type(cfg) == "table" then cfg[key] else nil
	return if finite(value) and value > 0 then value else 1
end

local function bonus(cfg: any, key: string): number
	local value = if type(cfg) == "table" then cfg[key] else nil
	return if finite(value) and value > 0 then value else 0
end

-- 0..1; NaN and non-numbers are 0.
local function fraction(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

function Pay.reward(args: RewardArgs): Reward
	local cfg = args.Cfg
	local patience = fraction(args.PatienceLeft)
	local tips = math.max(0, math.floor(numberOr(args.Tips, 0)))

	local items = math.clamp(math.floor(numberOr(args.Items, 1)), 1, Pay.MAX_ITEMS)
	local cheer = numberOr(args.Cheer, 1)
	cheer = if cheer >= 1 then math.min(cheer, Pay.MAX_CHEER) else 1
	local cashBoost = math.max(1, numberOr(args.CashBoost, 1))
	local tipsBoost = math.max(0, numberOr(args.TipsBoost, 0))
	local starsBoost = math.max(1, numberOr(args.StarsBoost, 1))

	local cash = math.max(0, numberOr(args.BasePay, 0))
	cash *= 1 + bonus(cfg, "RecipeItemBonus") * (items - 1)
	cash *= 1 + bonus(cfg, "QuickServeBonus") * patience
	cash *= 1 + bonus(cfg, "TipsPerLevel") * tips + tipsBoost
	cash *= cheer
	if args.Night == true then
		cash *= multiplier(cfg, "NightPayMultiplier")
	end
	local variantKey = if type(args.Variant) == "string" then VARIANT_MULTIPLIER[args.Variant] else nil
	if variantKey then
		cash *= multiplier(cfg, variantKey)
	end
	if args.Visitor == true then
		cash *= multiplier(cfg, "VisitorMultiplier")
	end
	cash *= cashBoost

	local stars = Pay.STARS_DAY
	if args.Regular == true or args.Visitor == true then
		stars = Pay.STARS_SPECIAL
	elseif args.Night == true then
		stars = Pay.STARS_NIGHT
	end

	return {
		Cash = math.max(1, math.floor(cash + 0.5)),
		Stars = math.max(stars, math.floor(stars * starsBoost + 0.5)),
	}
end

return Pay
