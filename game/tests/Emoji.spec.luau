--!nocheck
-- Roblox draws emoji from its own font, and that font has no glyph for some newer emoji: they show as an empty box.
-- Found in the Real Clinic Studio test (2026-11-17) by rendering every emoji in src on one screen: these six showed
-- as boxes, and the X-ray tool card was blank. Their stand-ins (also checked in Studio): 🩻 -> 📸, 🛗 -> ↕️,
-- 🪼 -> 🍓, 🪴 -> 🌳, 🫧 -> 🧼, ➜ -> →. Also Unicode 13+ ones like 🩼 🫁 (seen as boxes in the same test).
-- Before adding a new emoji, render it in Studio once; if it shows a box, add it here.

local fs = require("@lune/fs")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")

local NO_GLYPH = { "🩻", "🛗", "🪼", "🪴", "🫧", "➜", "🩼", "🫁" }

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local root = string.gsub(World.find("src/server/Patients.luau"), "/server/Patients%.luau$", "")
local files: { string } = {}
walk(root, files)
table.sort(files)

T.describe("Emoji Roblox can draw", function()
	test("no src file uses an emoji that Roblox shows as an empty box", function()
		expect(#files > 100).toBe(true)
		local found: { string } = {}
		for _, path in files do
			local source = fs.readFile(path)
			for _, emoji in NO_GLYPH do
				if string.find(source, emoji, 1, true) then
					table.insert(found, path .. ": " .. emoji)
				end
			end
		end
		expect(found).toEqual({})
	end)
end)
