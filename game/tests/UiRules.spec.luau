--!nocheck
-- The integrator's whole-tree rules (look build plan §D I-3): tests/uirules over EVERY src/client file, and the
-- global constraints the source can show across all tasks at once (each task's own spec only reads its own files):
--   · no text under 18 px, no local tab or text-fit copies, radii from tokens, no panel header colour;
--   · every button Kind in the UI is a role (no candy kinds left anywhere);
--   · original only (red line 2): no cross glyph and no toy brand in any shipped file;
--   · one tab column: nobody wraps Modal.tabs in a second scroller (it scrolls on its own);
--   · the rarity frame is still (the motion budget: a list shows dozens of them);
--   · the Real Clinic's words (design §12): no client string says cure (`%f[%a][Cc]ure`, any case: CURED! too).
--     Internal names stay (the Cured remote and save field, CureFX, the goal kinds "Cure"/"CureWing"), so a string
--     that is one identifier is an id, not words. Developer output (warn, print, error) isn't shown to players. The
--     game's title "Cure a Creature" stays until both brothers decide (design §2 non-goals, OPEN #12). A line that
--     must keep the word on purpose ends with "-- uirules: allow Cure".

local fs = require("@lune/fs")

local T = require("./expect")
local UiRules = require("./uirules")
local expect, test = T.expect, T.test

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

-- The string literals on one line of code ("...", '...' or `...`), outside a `--` comment.
local function literals(line: string): { string }
	local out = {}
	local quote: string? = nil
	local start = 0
	local i = 1
	while i <= #line do
		local c = string.sub(line, i, i)
		if quote then
			if c == "\\" then
				i += 1
			elseif c == quote then
				table.insert(out, string.sub(line, start, i - 1))
				quote = nil
			end
		elseif c == '"' or c == "'" or c == "`" then
			quote = c
			start = i + 1
		elseif c == "-" and string.sub(line, i + 1, i + 1) == "-" then
			break
		end
		i += 1
	end
	return out
end

local DEVELOPER_OUTPUT = { "warn(", "print(", "error(", "debug.profilebegin(" }
local TITLE = "cure a creature" -- the game's name, kept until both brothers rename it (OPEN #12)

-- Every player-visible string that says cure, as "path:line  text".
local function cureWords(paths: { string }): { string }
	local found = {}
	for _, path in paths do
		local n = 0
		for line in string.gmatch(fs.readFile(root .. "/" .. path) .. "\n", "(.-)\r?\n") do
			n += 1
			local skip = string.match(line, "^%s*%-%-") ~= nil
				or string.find(line, "uirules: allow Cure", 1, true) ~= nil
			for _, call in DEVELOPER_OUTPUT do
				skip = skip or string.find(line, call, 1, true) ~= nil
			end
			if not skip then
				for _, text in literals(line) do
					local words = string.gsub(string.lower(text), TITLE, "")
					local isId = string.match(text, "^[%a_][%w_]*$") ~= nil
					if not isId and string.find(words, "%f[%a]cure") then
						table.insert(found, path .. ":" .. n .. "  " .. text)
					end
				end
			end
		end
	end
	return found
end

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

	test("treat, never cure: no client string says cure (Real Clinic design §12)", function()
		local found = cureWords(CLIENT)
		assert(#found == 0, "\n" .. table.concat(found, "\n"))
	end)

	test(
		"the cure scan itself: it finds words, any case, and lets ids, developer output and the title through",
		function()
			local function scan(text: string): number
				local count = 0
				for _, literal in literals(text) do
					local words = string.gsub(string.lower(literal), TITLE, "")
					if not string.match(literal, "^[%a_][%w_]*$") and string.find(words, "%f[%a]cure") then
						count += 1
					end
				end
				return count
			end
			expect(scan('label.Text = "Cure 5 patients"')).toBe(1)
			expect(scan('title.Text = "CURED! 🎉"')).toBe(1)
			expect(scan("x = 'all cured'")).toBe(1)
			expect(scan('Remotes.Cured, "Cured", "CureFX", "CureWing"')).toBe(0)
			expect(scan('Text = "Welcome to Cure a Creature!"')).toBe(0)
			expect(scan('Text = "Treat 5 patients" -- "cure" in a comment')).toBe(0)
			expect(scan('Text = "Secure the door"')).toBe(0) -- not a word start
		end
	)

	test("the rarity frame is still: Kit.rarityFrame starts no job on the shared loop", function()
		local kit = fs.readFile(root .. "/src/client/UI/Kit.luau")
		local first = string.find(kit, "function Kit.rarityFrame", 1, true)
		local last = first and string.find(kit, "\nend\n", first, true)
		assert(first and last, "Kit.rarityFrame not found")
		local body = string.sub(kit, first, last)
		assert(not string.find(body, "addJob", 1, true), "Kit.rarityFrame loops again")
	end)
end)
