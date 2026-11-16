--!strict
-- Stations: where you hold to make a treatment item (build plan §B2).
-- Uses Color3, so it is Roblox-only: Lune specs must not require it.
-- Iterate `Stations.Order` for display order; `for id, station in Stations` yields only stations.

export type StationId = string
export type Station = {
	Name: string,
	Icon: string,
	Item: string, -- the ItemId this station makes (Data/Items)
	Color: Color3, -- ailments treated here share this colour, so kids can match by colour
}

local ENTRIES: { [StationId]: Station } = {
	Remedy = { Name = "Remedy Bench", Icon = "🧪", Item = "Potion", Color = Color3.fromRGB(176, 124, 255) },
	Plaster = { Name = "Plaster Table", Icon = "🩹", Item = "Plaster", Color = Color3.fromRGB(255, 150, 100) },
	Bath = { Name = "Warm Bath", Icon = "🛁", Item = "Bubbles", Color = Color3.fromRGB(80, 196, 240) },
	Cocoa = { Name = "Cocoa Corner", Icon = "☕", Item = "Cocoa", Color = Color3.fromRGB(196, 132, 84) },
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
