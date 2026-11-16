--!strict
-- Items: what a station makes and you carry to a patient. Lune-safe (no Roblox types).
-- The `Carry` player attribute is a comma-joined list of these ids, e.g. "Potion,Plaster".

export type ItemId = string
export type Item = {
	Name: string,
	Icon: string, -- shown above your head and on the HUD while carrying
	Station: string, -- StationId that makes it
}

local ENTRIES: { [ItemId]: Item } = {
	Potion = { Name = "Potion", Icon = "🧪", Station = "Remedy" },
	Plaster = { Name = "Plaster", Icon = "🩹", Station = "Plaster" },
	Bubbles = { Name = "Bubbles", Icon = "🛁", Station = "Bath" }, -- the Warm Bath's own icon: one picture per treatment
	Cocoa = { Name = "Cocoa", Icon = "☕", Station = "Cocoa" },
}

local ORDER = { "Potion", "Plaster", "Bubbles", "Cocoa" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { ItemId }, [ItemId]: Item }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
