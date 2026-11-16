--!strict
-- What one cure pays (build plan §B6). Pure: no Roblox services, no requires, so Lune can test it.
--   Pay.reward(args): { Cash: number, Stars: number }
--
-- Cash = BasePay
--      x (1 + QuickServeBonus x PatienceLeft)   cure while they still have patience: up to +50%
--      x (1 + TipsPerLevel x Tips)              the clinic's Tip Jar level: +20% each
--      x NightPayMultiplier                     night patients
--      x SparklyMultiplier / FrostyMultiplier   a rare variant
--      x VisitorMultiplier                      Today's Visitor
-- rounded to a whole number, and never below 1.
-- Stars = 3 for a regular or Today's Visitor, 2 at night, otherwise 1. The best reason wins; they don't add up.
--
-- Every input is untrusted: a junk number falls back to its neutral value (patience 0, tips 0) and a missing
-- Cfg field counts as "no bonus", so a bad call pays a little instead of erroring mid-cure.

export type Cfg = {
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
	Cfg: Cfg, -- Shared/Config
}

export type Reward = { Cash: number, Stars: number }

local Pay = {}

Pay.STARS_DAY = 1
Pay.STARS_NIGHT = 2
Pay.STARS_SPECIAL = 3 -- a regular or Today's Visitor

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

	local cash = math.max(0, numberOr(args.BasePay, 0))
	cash *= 1 + bonus(cfg, "QuickServeBonus") * patience
	cash *= 1 + bonus(cfg, "TipsPerLevel") * tips
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

	local stars = Pay.STARS_DAY
	if args.Regular == true or args.Visitor == true then
		stars = Pay.STARS_SPECIAL
	elseif args.Night == true then
		stars = Pay.STARS_NIGHT
	end

	return {
		Cash = math.max(1, math.floor(cash + 0.5)),
		Stars = stars,
	}
end

return Pay
