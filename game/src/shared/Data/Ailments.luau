--!strict
-- Ailments: what's wrong with a patient, shown as one big icon in its station's colour (build plan §B2).
-- Uses Color3 (from Stations), so it is Roblox-only: Lune specs must not require it.
-- Cartoon care only (Rated Minimal): nothing gross, scary or medical-needle-ish.
--
-- Recipe (depth update §1): the items a patient with this ailment needs, 1-3, in order. Item 1 is always the
-- treating station's own item (so the badge colour still matches). Each item is one short mini-game at the Counter.
-- By wing: Starter 1 item · Bath 2 · Winter 2 · Night 2 (Night patients come to every clinic, so their recipes use
-- First-Aid Stand items only). The hospital level cuts recipes (Data/Levels RecipeCap: Lv 1 -> 1 item, Lv 2 -> 2,
-- Lv 3 -> 3), so a new player only ever sees one item. Regulars have their own (Data/Regulars). Keep each entry on
-- one line: tests/Data.spec reads the recipes from this file's text (Lune can't load Color3).

local Stations = require(script.Parent.Stations)

export type AilmentId = string
export type Ailment = {
	Name: string, -- for builders and tooltips; players read the icon
	Icon: string,
	Color: Color3, -- always the colour of the station that treats it
	Station: string, -- StationId
	Recipe: { string }, -- ItemIds, 1-3; Recipe[1] is the station's own item
}

local function ailment(name: string, icon: string, station: string, recipe: { string }): Ailment
	local stationData = Stations[station]
	assert(stationData, "Unknown station " .. station)
	assert(recipe[1] == stationData.Item, name .. ": recipe item 1 must be " .. stationData.Item)
	return { Name = name, Icon = icon, Color = stationData.Color, Station = station, Recipe = recipe }
end

local ENTRIES: { [AilmentId]: Ailment } = {
	-- Remedy Bench (Potion)
	Hiccups = ailment("Hiccups", "❗", "Remedy", { "Potion" }),
	Sneezes = ailment("Sneezes", "🤧", "Remedy", { "Potion" }),
	Cough = ailment("Cough", "😷", "Remedy", { "Potion", "Plaster" }), -- Night: a warm chest plaster
	-- Plaster Table (Plaster)
	Bump = ailment("Bump", "🤕", "Plaster", { "Plaster" }),
	Scrape = ailment("Scrape", "😢", "Plaster", { "Plaster" }),
	LostGlow = ailment("Lost glow", "🌑", "Plaster", { "Plaster", "Potion" }), -- Night: a glow sticker, glow drops
	-- Warm Bath (Bubbles)
	Sticky = ailment("Sticky", "🍯", "Bath", { "Bubbles", "Potion" }),
	Muddy = ailment("Muddy", "🐾", "Bath", { "Bubbles", "Plaster" }),
	-- Cocoa Corner (Cocoa)
	Chills = ailment("Chills", "🥶", "Cocoa", { "Cocoa", "Potion" }),
	FrozenNose = ailment("Frozen nose", "❄️", "Cocoa", { "Cocoa", "Plaster" }),
}

local ORDER = { "Hiccups", "Sneezes", "Cough", "Bump", "Scrape", "LostGlow", "Sticky", "Muddy", "Chills", "FrozenNose" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { AilmentId }, [AilmentId]: Ailment }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
