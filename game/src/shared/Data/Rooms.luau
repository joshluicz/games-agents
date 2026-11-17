--!strict
-- Rooms: prebuilt modules that unlock into fixed slots on your plot (build plan §B2, design §5.10).
-- Each room adds stations (so new cases, so new patients), beds and decor slots. Lune-safe.
--
-- A room is a Model `Room_<RoomId>` with PrimaryPart `Floor`, placed so Floor.CFrame == its slot's CFrame.
-- Inside: `Station_<StationId>` Parts, `Bed_<n>` Parts and invisible `DecorSlot_<n>` Parts, n from 1.
-- A placeholder is built from these counts unless ServerStorage.ClinicKit.<RoomId> exists.
-- The Real Clinic (design §8.2, §15 #5; Server/PlotBuilder): the Bath Room, the Cozy Ward and the Winter Wing are
-- fit-outs INSIDE the Building's ground floor (each behind its own door, shut until the room is owned), the Garden is
-- behind the Building and the Stand is the forecourt at the front doors.
--   · The Stand's Stations and Beds are what the free clinic has, and the Building builds them (Station_Remedy in the
--     dispensary, Station_Plaster on the supply shelf, the ward beds upstairs from Lv 2), so the Stand's fit-out
--     holds only its decor slots.
--   · The Cozy Ward's 2 Beds are its 2 exam bays' beds (ExamBay_W1, ExamBay_W2: Shared/Logic/Building.BAYS with
--     Room = "Ward"), not recovery beds: buying it means more patients at once, as its beds did before.

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
	-- "Winter": can only be bought while Workspace.IsWinter is true (once owned, it stays). Unused today: the
	-- Winter Wing stays in the game all year (design §5.8, memory-20261116-005); only its Frosty variants, snow
	-- and the winter event come and go with Workspace.IsWinter. Kept for a future seasonal room.
	Season: string?,
	-- The hospital level a room needs (Data/Levels; nil = 1). Its ⭐ gate still applies too (depth update §3).
	Level: number?,
	-- What the room adds that its icons can't say, in a few words (the Shop's note shows it beside them).
	Adds: string?,
}

local ENTRIES: { [RoomId]: Room } = {
	Stand = {
		-- The forecourt at the front doors (its decor slots stand either side of the canopy). The free clinic's
		-- own name and icon are Data/Levels' (Lv 1 "Clinic"); this one only labels its decor spots: 🚪 1 and 🚪 2.
		Name = "Front Entrance",
		Icon = "🚪", -- no cross anywhere (look plan, original only)
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
		Beds = 2, -- its 2 exam bays' beds (ExamBay_W1, ExamBay_W2): working from Lv 1
		DecorSlots = 2,
		Wing = "Starter",
		Adds = "+2 exam bays",
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
		Level = 3, -- the Hospital
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
