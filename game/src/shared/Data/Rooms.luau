--!strict
-- Rooms: prebuilt modules that unlock into fixed slots on your plot (build plan §B2, design §5.10).
-- Each room adds stations (so new ailments, so new patients), beds and decor slots. Lune-safe.
--
-- A room is a Model `Room_<RoomId>` with PrimaryPart `Floor`, placed so Floor.CFrame == its slot's CFrame.
-- Inside: `Station_<StationId>` Parts, `Bed_<n>` Parts and invisible `DecorSlot_<n>` Parts, n from 1.
-- A placeholder is built from these counts unless ServerStorage.ClinicKit.<RoomId> exists.

export type RoomId = string
export type Room = {
	Name: string,
	Icon: string,
	Slot: string, -- SlotId: the plot has an invisible Part `Slots.RoomSlot_<SlotId>`
	Price: number, -- cash; 0 = free
	StarsNeeded: number, -- Clinic Stars needed to buy
	Stations: { string }, -- StationIds
	Beds: number,
	DecorSlots: number,
	Wing: string, -- WingId
	Season: string?, -- "Winter": can only be bought while Workspace.IsWinter is true (once owned, it stays)
}

local ENTRIES: { [RoomId]: Room } = {
	Stand = {
		Name = "First-Aid Stand",
		Icon = "⛑️",
		Slot = "Stand",
		Price = 0,
		StarsNeeded = 0,
		Stations = { "Remedy", "Plaster" },
		Beds = 1,
		DecorSlots = 2,
		Wing = "Starter",
	},
	BathRoom = {
		Name = "Bath Room",
		Icon = "🛁",
		Slot = "A",
		Price = 150,
		StarsNeeded = 10,
		Stations = { "Bath" },
		Beds = 0,
		DecorSlots = 1,
		Wing = "Bath",
	},
	Ward = {
		Name = "Cozy Ward",
		Icon = "🛏️",
		Slot = "B",
		Price = 300,
		StarsNeeded = 25,
		Stations = {},
		Beds = 2,
		DecorSlots = 2,
		Wing = "Starter",
	},
	WinterWing = {
		Name = "Winter Wing",
		Icon = "❄️",
		Slot = "C",
		Price = 500,
		StarsNeeded = 40,
		Stations = { "Cocoa" },
		Beds = 1,
		DecorSlots = 2,
		Wing = "Winter",
		Season = "Winter",
	},
	Garden = {
		Name = "Sunny Garden",
		Icon = "🌻",
		Slot = "D",
		Price = 800,
		StarsNeeded = 70,
		Stations = {},
		Beds = 0,
		DecorSlots = 3,
		Wing = "Starter",
	},
}

local ORDER = { "Stand", "BathRoom", "Ward", "WinterWing", "Garden" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { RoomId }, [RoomId]: Room }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
