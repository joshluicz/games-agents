--!strict
-- Items: what you carry to a patient in an exam bay (Real Clinic build plan, contract C3; design §7). Lune-safe (no
-- Roblox types). The `Carry` player attribute is a comma-joined list of these ids, e.g. "Plaster,CoughSyrup".
-- Iterate `Items.Order`; `for id, item in Items` yields only items.
--
--   Kind "Supply"    taken from its station (a hold prompt), then given at the bay with its own short game (Game, a
--                    GameId of Logic/MiniGame). Maker nurses stock these into the nurse tray.
--   Kind "Medicine"  made only by the player at the dispensary (station `Remedy`): pick the bottle, measure the dose.
--                    Handing one over plays no game (no Game). Bottle is its bottle's colour (hex) on the shelf.
-- Every item has an icon of its own (design §7): a plan chip, the dispensary prompt and the "This one needs ..." toast
-- show an item by its icon alone, so two medicines never share one (🧴 cough syrup / 🍃 soothing cream, 💊 fever
-- medicine / 🌼 pain relief).
-- Nothing here is a needle or anything scary: plasters, ice, bandages, a cast, a bath, a hot drink and gentle
-- medicines (design §2).

export type ItemId = string
export type Item = {
	Name: string,
	Icon: string, -- shown above your head, on the HUD while carrying, and on a patient's plan
	Station: string, -- StationId that makes it
	Kind: "Supply" | "Medicine",
	Game: string?, -- a supply's GameId; nil for a medicine
	Bottle: string?, -- a medicine's bottle colour, "#RRGGBB"
}

local ENTRIES: { [ItemId]: Item } = {
	-- Supplies
	Plaster = { Name = "Plaster", Icon = "🩹", Station = "Plaster", Kind = "Supply", Game = "Plaster" },
	Ice = { Name = "Ice pack", Icon = "🧊", Station = "Ice", Kind = "Supply", Game = "Ice" },
	Bandage = { Name = "Bandage", Icon = "🧻", Station = "Bandage", Kind = "Supply", Game = "Bandage" },
	Cast = { Name = "Cast", Icon = "🦴", Station = "Cast", Kind = "Supply", Game = "Cast" },
	Bubbles = { Name = "Bath foam", Icon = "🛁", Station = "Bath", Kind = "Supply", Game = "Bath" },
	Cocoa = { Name = "Hot chocolate", Icon = "☕", Station = "Cocoa", Kind = "Supply", Game = "Cocoa" },
	-- Medicines (the dispensary)
	CoughSyrup = { Name = "Cough syrup", Icon = "🧴", Station = "Remedy", Kind = "Medicine", Bottle = "#B56BE0" },
	FeverMeds = { Name = "Fever medicine", Icon = "💊", Station = "Remedy", Kind = "Medicine", Bottle = "#FF7A59" },
	EarDrops = { Name = "Ear drops", Icon = "💧", Station = "Remedy", Kind = "Medicine", Bottle = "#4DB8FF" },
	Lozenges = { Name = "Throat lozenges", Icon = "🍬", Station = "Remedy", Kind = "Medicine", Bottle = "#FFC53D" },
	Cream = { Name = "Soothing cream", Icon = "🍃", Station = "Remedy", Kind = "Medicine", Bottle = "#5FD3A8" },
	PainRelief = { Name = "Pain relief", Icon = "🌼", Station = "Remedy", Kind = "Medicine", Bottle = "#FF8FC7" },
}

local ORDER = {
	"Plaster",
	"Ice",
	"Bandage",
	"Cast",
	"Bubbles",
	"Cocoa",
	"CoughSyrup",
	"FeverMeds",
	"EarDrops",
	"Lozenges",
	"Cream",
	"PainRelief",
}

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
