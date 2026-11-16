--!strict
-- The Branch Ability Tree's rules (Progression v2 build plan §B5/§B7; design §7). Pure: no Roblox services, no
-- requires. `tree` is a save's Rebirth.Tree ({ [NodeId]: rank }), `nodes` Shared/Data/Tree.Nodes (read with rawget,
-- so "Order" is never a node). Every function returns new tables; inputs are never changed.
--
--   Tree.CAPSTONE_NEEDS = 6                      points spent in a branch before its capstone (Data/Tree.CapstoneNeeds;
--                                                Tree.spec checks they match)
--   Tree.canBuy(tree, points, nodeId, nodes): (ok, message)
--       a known node ("Oops! Try again.") · not at its Max ("Max rank!") · a capstone needs CAPSTONE_NEEDS points spent
--       in its own branch ("Need 6 🌳 in Care") · points >= its Cost ("Need 🌳2"). "" when ok
--   Tree.buy(tree, points, nodeId, nodes): (tree, points)   one more rank and the points left (unchanged copies when
--                                                canBuy says no)
--   Tree.refund(tree, nodes): number             every point back: rank x Cost for known nodes, 1 a rank for unknown
--                                                ones (a node renamed or removed is refunded too)
--   Tree.spent(tree, nodes, branch): number      points spent in one branch ("Care" | "Speed" | "Fortune")
--   Tree.effects(tree, nodes): { [EffectKey]: number }   rank x Value summed per Effect (Data/Tree): Patience,
--                                                Tips, MakeSpeed, Cash, Stars (percent), Ease, Lift, Bargain
--                                                (fractions), Walk (studs a second), DoubleShift (x1.25 when bought:
--                                                the Value, not summed), TwinCounters / LuckyStock (1 when bought)

local Tree = {}

Tree.CAPSTONE_NEEDS = 6

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function rankOf(tree: any, nodeId: string): number
	return if type(tree) == "table" then math.max(0, math.floor(num(tree[nodeId], 0))) else 0
end

local function node(nodes: any, nodeId: any): any
	if type(nodes) ~= "table" or type(nodeId) ~= "string" then
		return nil
	end
	local value = rawget(nodes, nodeId)
	return if type(value) == "table" then value else nil
end

local function copy(tree: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(tree) == "table" then
		for key, rank in tree do
			if type(key) == "string" then
				out[key] = rank
			end
		end
	end
	return out
end

function Tree.spent(tree: any, nodes: any, branch: string): number
	local total = 0
	if type(tree) ~= "table" then
		return 0
	end
	for nodeId in tree do
		local def = node(nodes, nodeId)
		if def and def.Branch == branch then
			total += rankOf(tree, nodeId) * math.max(0, num(def.Cost, 1))
		end
	end
	return total
end

function Tree.canBuy(tree: any, points: number, nodeId: string, nodes: any): (boolean, string)
	local def = node(nodes, nodeId)
	if not def then
		return false, "Oops! Try again."
	end
	if rankOf(tree, nodeId) >= math.max(1, num(def.Max, 1)) then
		return false, "Max rank!"
	end
	if def.Capstone == true and Tree.spent(tree, nodes, def.Branch) < Tree.CAPSTONE_NEEDS then
		return false, "Need " .. Tree.CAPSTONE_NEEDS .. " 🌳 in " .. tostring(def.Branch)
	end
	local cost = math.max(0, num(def.Cost, 1))
	if num(points, 0) < cost then
		return false, "Need 🌳" .. cost
	end
	return true, ""
end

function Tree.buy(tree: any, points: number, nodeId: string, nodes: any): ({ [string]: number }, number)
	local out = copy(tree)
	local left = math.max(0, math.floor(num(points, 0)))
	if not Tree.canBuy(tree, left, nodeId, nodes) then
		return out, left
	end
	local def = node(nodes, nodeId)
	out[nodeId] = rankOf(tree, nodeId) + 1
	return out, left - math.max(0, num(def.Cost, 1))
end

function Tree.refund(tree: any, nodes: any): number
	local total = 0
	if type(tree) ~= "table" then
		return 0
	end
	for nodeId in tree do
		if type(nodeId) == "string" then
			local def = node(nodes, nodeId)
			local cost = if def then math.max(0, num(def.Cost, 1)) else 1
			total += rankOf(tree, nodeId) * cost
		end
	end
	return total
end

function Tree.effects(tree: any, nodes: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(tree) ~= "table" then
		return out
	end
	for nodeId in tree do
		local def = node(nodes, nodeId)
		local rank = math.min(rankOf(tree, nodeId), if def then math.max(1, num(def.Max, 1)) else 0)
		if def and rank > 0 and type(def.Effect) == "string" then
			local value = num(def.Value, 0)
			if def.Effect == "DoubleShift" then
				out.DoubleShift = value
			elseif def.Effect == "TwinCounters" or def.Effect == "LuckyStock" then
				out[def.Effect] = 1
			else
				out[def.Effect] = (out[def.Effect] or 0) + value * rank
			end
		end
	end
	return out
end

return Tree
