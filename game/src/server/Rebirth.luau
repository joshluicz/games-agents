--!strict
-- Rebirths: "🏢 Open a new branch" (Progression v2 build plan §B3/§B4/§B8; design §7/§8, memory-20261116-017/-019).
-- Server only. OWNER: T2. The rules are Logic/Rebirth and Logic/Tree (Lune-tested); the content is Data/Perks,
-- Data/Tree and Data/Themes. Optional and never pushed (red line 3): one gentle toast ever, no dots, no repeats.
--
-- STUB (T2): the Foundation's safe defaults, so everything requires and boots. Until T2 lands, OpenBranch,
-- ChoosePerk, BuyNode, ResetTree, SetTheme and ClaimBranchNurse answer "Coming soon!" (Shared/Remotes' default).
--
--   Rebirth.start()                 wires OpenBranch, ChoosePerk, BuyNode, ResetTree, SetTheme and ClaimBranchNurse;
--                                   places the mascot (R5+); sets WalkBoost and the walk speed on CharacterAdded, the
--                                   plot's Branches attribute and the sign's BranchBadge; the once-ever Told toast
--   Rebirth.count(p): number        the player's Rebirth.Count (0 until their data loads)
--   Rebirth.effects(p): Effects     Logic/Rebirth.effects on the live save (neutral until it loads)
--   Rebirth.open(p, free?): (ok, message)
--                                   1. the §B3 OpenBranch checks  2. Patients.reopen(p)  3. re-check  4. ONE update:
--                                   Logic/Rebirth.apply with an offer rolled by the server's Random  5. Plots.syncRooms
--                                   6. PlayerData.saveNow  7. Celebrate Rebirth, then Unlock per new unlock; Reborn
--   Rebirth.Reborn: Signal (p, count)
--   Rebirth.adminRebirth(p)         Admin "Rebirth": open(p, true) (no Lv 5, no cost)
--   Rebirth.adminPoints(p)          Admin "AddTreePoints": +3 points
-- Requires Patients, Treatment, Nurses, Plots (and PlayerData, Levels...). No module requires Rebirth (but Admin).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local RebirthLogic = require(Shared.Logic.Rebirth)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local PlayerData = require(script.Parent.PlayerData)

local Rebirth = {}

Rebirth.Reborn = Signal.new()

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

function Rebirth.count(player: Player): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return if data then data.Rebirth.Count else 0
end

function Rebirth.effects(player: Player): RebirthLogic.Effects
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return RebirthLogic.effects(data, Config, PerksData, TreeData)
end

-- STUB (T2)
function Rebirth.open(_player: Player, _free: boolean?): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T2)
function Rebirth.adminRebirth(player: Player): (boolean, string)
	return Rebirth.open(player, true)
end

-- STUB (T2)
function Rebirth.adminPoints(_player: Player): (boolean, string)
	return false, Remotes.SOON
end

function Rebirth.start() end

return Rebirth
