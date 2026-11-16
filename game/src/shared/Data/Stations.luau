--!strict
-- Stations: where you hold to make a treatment item (build plan §B2).
-- Uses Color3 (from Shared/Palette), so it is Roblox-only: Lune specs must not require it.
-- Iterate `Stations.Order` for display order; `for id, station in Stations` yields only stations.
--
-- Colours are candy pop (memory-20261116-007): four full-saturation candy colours, as far apart as the set
-- allows, so a kid matches a patient's badge ring to its station at a glance. None of them is green, yellow or
-- red, which the patience ring uses.

local Palette = require(script.Parent.Parent:WaitForChild("Palette"))
local Candy = Palette.Candy

export type StationId = string
export type Station = {
	Name: string,
	Icon: string,
	Item: string, -- the ItemId this station makes (Data/Items)
	Color: Color3, -- ailments treated here share this colour, so kids can match by colour
}

local ENTRIES: { [StationId]: Station } = {
	Remedy = { Name = "Remedy Bench", Icon = "🧪", Item = "Potion", Color = Candy.Purple },
	Plaster = { Name = "Plaster Table", Icon = "🩹", Item = "Plaster", Color = Candy.Pink },
	Bath = { Name = "Warm Bath", Icon = "🛁", Item = "Bubbles", Color = Candy.Blue },
	Cocoa = { Name = "Cocoa Corner", Icon = "☕", Item = "Cocoa", Color = Candy.Orange },
}

local ORDER = { "Remedy", "Plaster", "Bath", "Cocoa" }

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
