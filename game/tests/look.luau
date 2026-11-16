--!nocheck
-- Colour and size helpers for the look specs (not a spec itself; look build plan §D Task 0). They take Lune's roblox
-- Color3 (R, G, B in 0..1) or any { R, G, B } table, and the mock parts of tests/worldmock.
--
--   Look.hsv(color): (h, s, v)          hue in degrees 0..360 (0 for a grey), saturation and value in 0..1
--   Look.luma(color): number            Rec. 601 luma, 0..255 (what the screenshot stats use)
--   Look.maxChannel(color): number      the biggest of R, G, B as 0..255 (a "bleached" colour has one near 255)
--   Look.hueGap(a, b): number           degrees between two hues, the short way round (0..180)
--   Look.round(n, digits?): number      rounded to `digits` decimals (2 unless given): the specs compare V at 0.01
--   Look.isBigFace(part, area): boolean any face of the part is bigger than `area` studs^2
--   Look.fromHex("#RRGGBB"): { R, G, B }   a plain table (for specs that have no Color3)

local Look = {}

function Look.fromHex(hex: string)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	assert(r, "not a hex colour: " .. tostring(hex))
	return { R = tonumber(r, 16) / 255, G = tonumber(g, 16) / 255, B = tonumber(b, 16) / 255 }
end

function Look.hsv(color): (number, number, number)
	local r, g, b = color.R, color.G, color.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta > 1e-9 then
		if max == r then
			h = 60 * (((g - b) / delta) % 6)
		elseif max == g then
			h = 60 * ((b - r) / delta + 2)
		else
			h = 60 * ((r - g) / delta + 4)
		end
	end
	local s = if max > 1e-9 then delta / max else 0
	return h % 360, s, max
end

function Look.luma(color): number
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) * 255
end

function Look.maxChannel(color): number
	return math.floor(math.max(color.R, color.G, color.B) * 255 + 0.5)
end

function Look.hueGap(a: number, b: number): number
	local gap = math.abs(a - b) % 360
	return if gap > 180 then 360 - gap else gap
end

function Look.round(n: number, digits: number?): number
	local scale = 10 ^ (digits or 2)
	return math.floor(n * scale + 0.5) / scale
end

function Look.isBigFace(part, area: number): boolean
	local s = part.Size
	return s.X * s.Y > area or s.X * s.Z > area or s.Y * s.Z > area
end

return Look
