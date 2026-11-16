--!strict
-- Nurses you own: equip slots, nurse workers on your plot, the nurse tray and the Nurse Journal (depth-update design
-- §2, build plan §B8). Server only. OWNER: T3. FOUNDATION STUB: every function exists with its final signature and a
-- safe default, so Treatment, Patients and NurseBelt can call them today.
--
--   Nurses.start()                              wires EquipNurse; spawns the equipped nurses on PlotAssigned (and
--                                               after an equip or a level-up), removes them on PlotReleased
--   Nurses.slots(p): number                     = Levels.slots(p) (slots = hospital level)
--   Nurses.equip(p, nurseId, on): (ok, message) Logic/Nurse.equip, saved in Data.Equipped
--   Nurses.grant(p, nurseId, price): (ok, message)
--                                               NurseBelt's hire: charge `price` and add one copy in ONE
--                                               PlayerData.update (Logic/Nurse.hire, NurseIndex "Hired"), then any
--                                               journal set due (cash + decor + JournalSets, same update); then the
--                                               NurseNews (Hired), Celebrate (NewNurse on a first copy, JournalSet)
--                                               remotes and the Hired signal
--   Nurses.markSeen(nurseId)                    a nurse stepped on the belt: every loaded player without a journal
--                                               entry for it gets "Seen" and a NurseNews (Seen)
--   Nurses.trayItems(plot): { ItemId }          the plot's nurse tray (Makers fill it; attribute NurseTray)
--   Nurses.takeFromTray(plot, itemId): boolean  removes one (Treatment, for a player's treat or a Healer's)
--   Nurses.cheer(plot): Types.Cheer             the best equipped Cheerer's multipliers ({ 1, 1 } when none); also
--                                               kept on the plot's CheerPatience and CheerTip attributes
--   Nurses.healed(plot, nurseId, items)         Treatment tells the Healer it delivered (play its hop)
--   Nurses.Heal                                 signal (plot, nurseId): a Healer is ready. Treatment delivers what
--                                               the front patient needs from the tray (rated OK, no tip, no combo)
--   Nurses.Hired                                signal (p, nurseId, level)
-- Nurses work only while the owner is in the server (their plot is released when they leave): no offline income.
-- Never requires Treatment or Patients (they require this): it reads the plot's FrontNeeds and QueueNeeds.

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Levels = require(script.Parent.Levels)

type Plot = Types.Plot

local Nurses = {}

Nurses.Heal = Signal.new()
Nurses.Hired = Signal.new()

function Nurses.slots(player: Player): number
	return Levels.slots(player)
end

function Nurses.equip(_player: Player, _nurseId: string, _on: boolean): (boolean, string)
	return false, Remotes.SOON -- T3
end

function Nurses.grant(_player: Player, _nurseId: string, _price: number): (boolean, string)
	return false, Remotes.SOON -- T3
end

function Nurses.markSeen(_nurseId: string) end

function Nurses.trayItems(_plot: Plot): { string }
	return {}
end

function Nurses.takeFromTray(_plot: Plot, _itemId: string): boolean
	return false
end

function Nurses.cheer(_plot: Plot): Types.Cheer
	return { Patience = 1, Tip = 1 }
end

function Nurses.healed(_plot: Plot, _nurseId: string, _items: { string }) end

function Nurses.start()
	Remotes.serve("EquipNurse", function(player: Player, nurseId: any, on: any)
		if type(nurseId) ~= "string" or #nurseId > 40 or type(on) ~= "boolean" then
			return false, Remotes.OOPS
		end
		return Nurses.equip(player, nurseId, on)
	end)
end

return Nurses
