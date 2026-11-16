--!nocheck
-- The integrator's whole-tree rules (look build plan §D I-3): tests/uirules over EVERY src/client file, and the
-- global constraints the source can show across all tasks at once (each task's own spec only reads its own files):
--   · no text under 18 px, no local tab or text-fit copies, radii from tokens, no panel header colour;
--   · every button Kind in the UI is a role (no candy kinds left anywhere);
--   · original only (red line 2): no cross glyph and no toy brand in any shipped file;
--   · one tab column: nobody wraps Modal.tabs in a second scroller (it scrolls on its own);
--   · the rarity frame is still (the motion budget: a list shows dozens of them).

local fs = require("@lune/fs")

local T = require("./expect")
local UiRules = require("./uirules")
local test = T.test

local root = if fs.isDir("src/client") then "." else "game"

local function walk(dir: string, out: { string }): { string }
	for _, name in fs.readDir(root .. "/" .. dir) do
		local path = dir .. "/" .. name
		if fs.isDir(root .. "/" .. path) then
			walk(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

-- The code of a file: comment lines dropped (a rule may be named in a comment).
local function code(path: string): string
	local lines = {}
	for line in string.gmatch(fs.readFile(root .. "/" .. path), "[^\n]+") do
		if not string.match(line, "^%s*%-%-") then
			table.insert(lines, line)
		end
	end
	return table.concat(lines, "\n")
end

local CLIENT = walk("src/client", {})
local ALL = walk("src", {})

T.describe("UI rules over the whole client (integrator)", function()
	test("there are client files to check", function()
		assert(#CLIENT >= 30, "only " .. #CLIENT .. " client files found")
	end)

	test("uirules: every src/client file", function()
		local violations = UiRules.check(CLIENT)
		assert(#violations == 0, "\n" .. UiRules.format(violations))
	end)

	test("every button Kind is a role (no candy kinds anywhere in the UI)", function()
		local candy = { "Good", "Danger", "Pink", "Purple", "Cyan", "Cash", "Card" }
		for _, path in CLIENT do
			local body = code(path)
			for _, kind in candy do
				assert(
					not string.find(body, 'Kind = "' .. kind .. '"', 1, true),
					path .. ': Kind "' .. kind .. '" is a candy kind, not a role'
				)
			end
		end
	end)

	test("original only: no cross glyph and no toy brand in any shipped file (comments included)", function()
		for _, path in ALL do
			local text = fs.readFile(root .. "/" .. path)
			for _, glyph in { "✚", "✙", "✛", "✜", "⛑" } do
				assert(not string.find(text, glyph, 1, true), path .. ": the glyph " .. glyph)
			end
			assert(not string.find(string.upper(text), "%f[%a]LEGO%f[%A]"), path .. ": say studs")
		end
	end)

	test("one tab column: Modal.tabs scrolls on its own, nobody wraps it in a second scroller", function()
		for _, path in CLIENT do
			local body = code(path)
			assert(not string.find(body, "TabScroll", 1, true), path .. ": a second tab scroller")
		end
		assert(string.find(code("src/client/UI/Modal.luau"), "AutomaticCanvasSize", 1, true), "Modal.tabs scrolls")
	end)

	test("the rarity frame is still: Kit.rarityFrame starts no job on the shared loop", function()
		local kit = fs.readFile(root .. "/src/client/UI/Kit.luau")
		local first = string.find(kit, "function Kit.rarityFrame", 1, true)
		local last = first and string.find(kit, "\nend\n", first, true)
		assert(first and last, "Kit.rarityFrame not found")
		local body = string.sub(kit, first, last)
		assert(not string.find(body, "addJob", 1, true), "Kit.rarityFrame loops again")
	end)
end)
