--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real pay maths and its spec (tests/Pay.spec.luau).
-- Pure: no Roblox services, no requires. Signature from build plan §B6.

export type RewardArgs = {
	BasePay: number,
	Tips: number, -- Tip Jar level
	PatienceLeft: number, -- 0..1
	Night: boolean,
	Variant: string?,
	Visitor: boolean,
	Regular: boolean,
	Cfg: any, -- Config (QuickServeBonus, TipsPerLevel, NightPayMultiplier, SparklyMultiplier, ...)
}

local Pay = {}

function Pay.reward(args: RewardArgs): { Cash: number, Stars: number }
	return { Cash = math.max(1, math.floor(args.BasePay)), Stars = 1 }
end

return Pay
