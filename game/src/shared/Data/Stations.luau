--!strict
-- Stations: where you get what a patient's plan needs (Real Clinic build plan, contract C3; design §7 and §9).
-- Uses Color3 (from Shared/Palette), so it is Roblox-only: Lune specs must not require it.
-- Iterate `Stations.Order`; `for id, station in Stations` yields only stations.
--
--   Item      the supply (Data/Items, Kind "Supply") you take here with a hold prompt; "" for the dispensary
--   Dispense  true: the dispensary. The player picks a medicine a bay patient needs, finds its bottle and measures
--             the dose (a Dispense session, Server/Treatment). Nurses never dispense
-- Where they stand: Plaster, Ice, Bandage, Cast and Remedy are in the Building (Logic/Building.STATIONS, as
-- `Station_<id>` parts with an `Open` attribute); Bath is in the Bath Room and Cocoa in the Winter Wing (the bought
-- rooms' fit-outs). Ids are alphanumeric: the parts are named `Station_<id>`.
--
-- Colours are candy pop (memory-20261116-007): full-saturation colours as far apart as the set allows, so a kid
-- matches a plan step's ring to its station at a glance. None of them is green, yellow or red, which the patience
-- ring uses.

local Palette = require(script.Parent.Parent:WaitForChild("Palette"))
local Candy = Palette.Candy

export type StationId = string
export type Station = {
	Name: string,
	Icon: string,
	Item: string, -- the supply ItemId this station gives (Data/Items); "" for the dispensary
	Color: Color3, -- plan steps made here share this colour, so kids can match by colour
	Dispense: boolean?, -- true: the dispensary (medicines; the player only)
}

local ENTRIES: { [StationId]: Station } = {
	Remedy = { Name = "Dispensary", Icon = "💊", Item = "", Color = Candy.Purple, Dispense = true },
	Plaster = { Name = "Plasters", Icon = "🩹", Item = "Plaster", Color = Candy.Pink },
	Ice = { Name = "Ice Packs", Icon = "🧊", Item = "Ice", Color = Candy.Cyan },
	Bandage = { Name = "Bandages", Icon = "🧻", Item = "Bandage", Color = Candy.Mint },
	Cast = { Name = "Cast Table", Icon = "🦴", Item = "Cast", Color = Color3.fromRGB(214, 170, 110) },
	Bath = { Name = "Warm Bath", Icon = "🛁", Item = "Bubbles", Color = Candy.Blue },
	Cocoa = { Name = "Cocoa Corner", Icon = "☕", Item = "Cocoa", Color = Candy.Orange },
}

local ORDER = { "Remedy", "Plaster", "Ice", "Bandage", "Cast", "Bath", "Cocoa" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { StationId }, [StationId]: Station }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
