--!strict
-- Ailments: what's wrong with a patient, shown as one big icon in its station's colour (build plan §B2).
-- Uses Color3 (from Stations), so it is Roblox-only: Lune specs must not require it.
-- Cartoon care only (Rated Minimal): nothing gross, scary or medical-needle-ish.

local Stations = require(script.Parent.Stations)

export type AilmentId = string
export type Ailment = {
	Name: string, -- for builders and tooltips; players read the icon
	Icon: string,
	Color: Color3, -- always the colour of the station that treats it
	Station: string, -- StationId
}

local function ailment(name: string, icon: string, station: string): Ailment
	local stationData = Stations[station]
	assert(stationData, "Unknown station " .. station)
	return { Name = name, Icon = icon, Color = stationData.Color, Station = station }
end

local ENTRIES: { [AilmentId]: Ailment } = {
	-- Remedy Bench (Potion)
	Hiccups = ailment("Hiccups", "❗", "Remedy"),
	Sneezes = ailment("Sneezes", "🤧", "Remedy"),
	Cough = ailment("Cough", "😷", "Remedy"),
	-- Plaster Table (Plaster)
	Bump = ailment("Bump", "🤕", "Plaster"),
	Scrape = ailment("Scrape", "😢", "Plaster"),
	LostGlow = ailment("Lost glow", "🌑", "Plaster"), -- a glow-sticker plaster
	-- Warm Bath (Bubbles)
	Sticky = ailment("Sticky", "🍯", "Bath"),
	Muddy = ailment("Muddy", "🐾", "Bath"),
	-- Cocoa Corner (Cocoa)
	Chills = ailment("Chills", "🥶", "Cocoa"),
	FrozenNose = ailment("Frozen nose", "❄️", "Cocoa"),
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
