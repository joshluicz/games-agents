--!strict
-- Stations: where you get what a patient's plan needs (Real Clinic build plan, contract C3; design §7 and §9).
-- Uses Color3 (from Shared/Palette), so it is Roblox-only: Lune specs must not require it.
-- Iterate `Stations.Order`; `for id, station in Stations` yields only stations.
--
--   Item      the supply (Data/Items, Kind "Supply") you take here with a hold prompt; "" for the dispensary
--   Dispense  true: the dispensary. The player picks a medicine a bay patient needs, finds its bottle and measures
--             the dose (a Dispense session, Server/Treatment). Nurses never dispense
-- Where they stand: ALL of them are in the Building (Logic/Building.STATIONS, as `Station_<id>` parts with an `Open`
-- attribute). Plaster, Ice and Bandage on the supply shelf, Cast in the X-ray room, Remedy at the dispensary counter;
-- Cocoa and Bath in the PANTRY, in the hall behind the supply shelf (Joshua, 2026-11-17: "minimise the patients
-- walking around. yes move the hot cocoa into like a pantry"; memory-20261117-006). The pantry's two open with their
-- rooms (Cocoa: the Winter Wing; Bath: the Bath Room), which no longer hold a station: they are themed recovery rooms
-- that bring their case pools. The ids, the items (Cocoa, Bubbles) and the `Made:<id>` stats are as they were.
-- Ids are alphanumeric: the parts are named `Station_<id>`.
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
	Bath = { Name = "Bath Foam", Icon = "🛁", Item = "Bubbles", Color = Candy.Blue },
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
