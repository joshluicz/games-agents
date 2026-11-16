--!strict
-- The tutorial's guide nurse (look build plan §B9; UI/Tutorial draws its portrait with Hud.portrait(Guide.Look)).
-- Lune-safe (hex colours). An ORIGINAL look in the nurses' format (Data/Nurses.Look: CreatureBuilder.buildLook and
-- Hud.portrait both draw it). It is NOT one of the hireable nurses: it never rides the belt, is never owned and has
-- no stats.
-- PLACEHOLDER: the name is never shown on screen. Joshua and his brother name and design the guide
-- (context/OPEN-QUESTIONS.md, look build plan §F8); until then the tutorial card shows only the face.

export type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
}

local Guide = {
	Name = "Guide Nurse", -- a placeholder: the UI never prints it
	Icon = "👩‍⚕️",
	-- A warm cream ball with teal accents and round ears: none of the 17 nurses has this body and accent pair.
	Look = table.freeze({
		Shape = "Ball",
		Body = "#FFE2B8",
		Accent = "#29BCCC",
		Ears = "Round",
		Top = "None",
		Extra = "None",
		Scale = 0.85,
	}) :: Look,
}

return table.freeze(Guide)
