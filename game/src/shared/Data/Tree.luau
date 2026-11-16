--!strict
-- The Branch Ability Tree (Progression v2 build plan §B5; design §7, memory-20261116-017/-019). Lune-safe.
-- Each rebirth gives Config.Rebirth.PointsPerRebirth points (3). A rank costs its node's Cost; a capstone (Cost 2,
-- one rank) needs CapstoneNeeds points spent in its own branch first. The whole tree is 33 points. Resetting is
-- free, any time, every point back (§E16). Nothing here changes any odds (§E5: Fortune never touches a roll).
--
--   Tree.Branches      { [BranchId]: { Name, Icon } } and Tree.BranchOrder (Care, Speed, Fortune)
--   Tree.Nodes         { [NodeId]: Node }, iterate Tree.Nodes.Order (by branch, capstone last)
--   Tree.CapstoneNeeds 6
-- Node:
--   Branch    "Care" | "Speed" | "Fortune"
--   Name, Icon, Text   the node (Text 6 words or fewer, per rank)
--   Max       ranks (3; a capstone 1)
--   Cost      points per rank (1; a capstone 2)
--   Capstone  true for the three capstones
--   Effect    the key it adds to (Logic/Tree.effects; Logic/Rebirth.effects merges it with the perks):
--             Patience, Tips, MakeSpeed, Cash, Stars (percent) · Ease (Perfect windows, a fraction) · Walk (studs a
--             second) · Lift (a fraction off the ride) · Bargain (a fraction off belt and Agency prices) ·
--             TwinCounters, LuckyStock (flags) · DoubleShift (nurse work speed x Value)
--   Value     per rank

export type NodeId = string
export type Node = {
	Branch: string,
	Name: string,
	Icon: string,
	Text: string,
	Max: number,
	Cost: number,
	Capstone: boolean,
	Effect: string,
	Value: number,
}
export type Branch = { Name: string, Icon: string }

local function rank(branch: string, name: string, icon: string, text: string, effect: string, value: number): Node
	return {
		Branch = branch,
		Name = name,
		Icon = icon,
		Text = text,
		Max = 3,
		Cost = 1,
		Capstone = false,
		Effect = effect,
		Value = value,
	}
end

local function capstone(branch: string, name: string, icon: string, text: string, effect: string, value: number): Node
	return {
		Branch = branch,
		Name = name,
		Icon = icon,
		Text = text,
		Max = 1,
		Cost = 2,
		Capstone = true,
		Effect = effect,
		Value = value,
	}
end

local NODES: { [NodeId]: Node } = {
	-- 💗 Care
	GentleWords = rank("Care", "Gentle Words", "💺", "Patients wait 10% longer", "Patience", 10),
	ThankYou = rank("Care", "Thank You", "💵", "Tips +10%", "Tips", 10),
	SteadyHands = rank("Care", "Steady Hands", "🎯", "Perfect windows 10% wider", "Ease", 0.1),
	TwinCounters = capstone("Care", "Twin Counters", "👯", "Treat the second patient too", "TwinCounters", 1),
	-- ⚡ Speed
	NimbleFingers = rank("Speed", "Nimble Fingers", "⚡", "Make 10% faster", "MakeSpeed", 10),
	QuickFeet = rank("Speed", "Quick Feet", "👟", "Walk a little faster", "Walk", 1),
	ExpressLift = rank("Speed", "Express Lift", "🛗", "Lift rides 20% shorter", "Lift", 0.2),
	DoubleShift = capstone("Speed", "Double Shift", "⏩", "Nurses work 25% faster", "DoubleShift", 1.25),
	-- 🍀 Fortune
	LuckyCoins = rank("Fortune", "Lucky Coins", "💰", "Cash +10%", "Cash", 10),
	StarShine = rank("Fortune", "Star Shine", "⭐", "Stars +10%", "Stars", 10),
	Bargain = rank("Fortune", "Bargain", "🏷️", "Nurses cost 5% less", "Bargain", 0.05),
	LuckyStock = capstone("Fortune", "Lucky Stock", "🍀", "2 Agency nurses just for you", "LuckyStock", 1),
}

local NODE_ORDER = {
	"GentleWords",
	"ThankYou",
	"SteadyHands",
	"TwinCounters",
	"NimbleFingers",
	"QuickFeet",
	"ExpressLift",
	"DoubleShift",
	"LuckyCoins",
	"StarShine",
	"Bargain",
	"LuckyStock",
}

local BRANCHES: { [string]: Branch } = {
	Care = { Name = "Care", Icon = "💗" },
	Speed = { Name = "Speed", Icon = "⚡" },
	Fortune = { Name = "Fortune", Icon = "🍀" },
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Nodes = { Order: { NodeId }, [NodeId]: Node }
type Module = {
	Branches: { [string]: Branch },
	BranchOrder: { string },
	Nodes: Nodes,
	CapstoneNeeds: number,
}
return freeze({
	Branches = BRANCHES,
	BranchOrder = { "Care", "Speed", "Fortune" },
	Nodes = setmetatable(NODES, { __index = { Order = freeze(NODE_ORDER) } }),
	CapstoneNeeds = 6,
}) :: Module
