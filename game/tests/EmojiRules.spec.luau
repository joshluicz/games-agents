--!nocheck
-- The emoji rules (docs/plan/2026-11-17-ui-direction.md §2 "The emoji rules" and §6; Joshua, memory-20261117-007:
-- "not to remove the emojis, but to use them correctly"). Emoji are the game's art, so they are nouns; they are
-- never punctuation. This spec holds the dictionary to that:
--   · UI/Icons.luau names each chrome emoji ONCE (one emoji, one idea; one idea, one emoji);
--   · the collision winners are the ones in the doc (§7.3), and every loser is retired to its winner;
--   · every emoji in it is one Roblox can draw (tests/Emoji.spec's no-glyph list);
--   · Icons.unit / level / needs glue a Unit to its number the same way everywhere;
--   · every Pure.TEXT table in the UI has at most one emoji per entry (a ratchet that starts at 0 everywhere);
--   · Kit, Modal and Theme type no emoji at all: the chrome reads Icons.
-- The per-line rules (TitleEmoji, LabelEmoji, LeadEmoji, TypedEmoji) are tests/uirules', run by UiRules.spec.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local UiRules = require("./uirules")
local expect, test = T.expect, T.test

local root = if fs.isDir("src/client") then "." else "game"
local function source(path: string): string
	return fs.readFile(root .. "/" .. path)
end

local Icons = luau.load(source("src/client/UI/Icons.luau"), { debugName = "Icons" })()

-- tests/Emoji.spec's list: Roblox's emoji font has no glyph for these (they show as an empty box).
local NO_GLYPH = (function(): { string }
	local text = source("tests/Emoji.spec.luau")
	local list = string.match(text, "local NO_GLYPH = {(.-)}")
	assert(list, "Emoji.spec's NO_GLYPH list not found")
	local out = {}
	for emoji in string.gmatch(list, '"([^"]+)"') do
		table.insert(out, emoji)
	end
	return out
end)()

local function bare(emoji: string): string
	return (string.gsub(emoji, "\u{FE0F}", ""))
end

local UI_FILES = (function(): { string }
	local out = {}
	for _, name in fs.readDir(root .. "/src/client/UI") do
		if string.sub(name, -5) == ".luau" then
			table.insert(out, "src/client/UI/" .. name)
		end
	end
	table.sort(out)
	return out
end)()

-- The entries of every `TEXT = {` / `Pure.TEXT = {` table in a file with more than one emoji, as "path:line  text".
local function crowdedText(path: string): { string }
	local found = {}
	local depth = 0 -- 0 = outside a TEXT table
	local n = 0
	for line in string.gmatch(source(path) .. "\n", "(.-)\r?\n") do
		n += 1
		local opens = string.find(line, "TEXT%s*=%s*[%w_%.]*%(?{") ~= nil
		if depth == 0 and not opens then
			continue
		end
		if not string.match(line, "^%s*%-%-") and not string.find(line, "uirules: allow LabelEmoji", 1, true) then
			for _, literal in UiRules.literals(line) do
				if Icons.count(literal.Text) > 1 then
					table.insert(found, path .. ":" .. n .. "  " .. literal.Text)
				end
			end
		end
		local code = string.gsub(line, '"[^"]*"', "")
		for _ in string.gmatch(code, "{") do
			depth += 1
		end
		for _ in string.gmatch(code, "}") do
			depth -= 1
		end
		depth = math.max(depth, 0)
	end
	return found
end

T.describe("UI/Icons: the chrome emoji dictionary", function()
	local list = Icons.list()

	test("it has the five roles' tables and the two marks", function()
		for _, role in { "Door", "Unit", "State", "Status", "Party", "Mark" } do
			assert(type(Icons[role]) == "table", "Icons." .. role)
			assert(table.find(Icons.ROLES, role), role .. " is listed in Icons.ROLES")
		end
		expect(#Icons.ROLES).toBe(6)
		assert(#list >= 25, "only " .. #list .. " icons")
	end)

	test("one emoji, one idea: no emoji is in the dictionary twice", function()
		local seen: { [string]: string } = {}
		for _, entry in list do
			local key = bare(entry.Emoji)
			local where = entry.Role .. "." .. entry.Name
			assert(seen[key] == nil, entry.Emoji .. " is both " .. tostring(seen[key]) .. " and " .. where)
			seen[key] = where
		end
	end)

	test("every entry is exactly one emoji and nothing else", function()
		for _, entry in list do
			local where = entry.Role .. "." .. entry.Name
			expect(Icons.count(entry.Emoji)).toBe(1)
			assert(Icons.clusters(entry.Emoji)[1] == entry.Emoji, where .. " has more than its emoji in it")
		end
	end)

	test("every emoji is one Roblox can draw (tests/Emoji.spec's no-glyph list)", function()
		assert(#NO_GLYPH >= 8, "the no-glyph list was not read")
		for _, entry in list do
			for _, missing in NO_GLYPH do
				assert(
					not string.find(entry.Emoji, missing, 1, true),
					entry.Role .. "." .. entry.Name .. " is " .. missing .. ", which Roblox shows as a box"
				)
			end
		end
		for retired in Icons.RETIRED do
			expect(Icons.count(retired)).toBe(1)
		end
	end)

	test(
		"the collision winners (doc §7.3): 🏥 level, 📖 Book, 📬 Mail, 🔁 again, 🏢 Branches only, ⭐ Stars only",
		function()
			expect(Icons.Unit.Level).toBe("🏥")
			expect(Icons.Door.Book).toBe("📖")
			expect(Icons.Door.Mail).toBe("📬")
			expect(Icons.Mark.Again).toBe("🔁")
			expect(Icons.Door.Branches).toBe("🏢")
			expect(Icons.Unit.Stars).toBe("⭐")
			expect(Icons.Unit.Cash).toBe("💰")
			expect(Icons.Unit.Tree).toBe("🌳")
			-- The Agency has its own door: not the Branches' building, not the Market's tag, not Cash.
			assert(Icons.Door.Agency ~= Icons.Door.Branches, "the Agency shares the Branches' icon")
			assert(Icons.Door.Agency ~= Icons.Door.Market, "the Agency shares the Market's icon")
			assert(Icons.Door.Agency ~= Icons.Unit.Cash, "the Agency shares Cash's icon")
			expect(Icons.State.Locked).toBe("🔒")
			expect(Icons.State.Done).toBe("✅")
			expect(Icons.State.Resting).toBe("💤")
			expect(Icons.Mark.Close).toBe("✖")
		end
	)

	test("every loser is retired to a real winner, and no retired emoji is still in the dictionary", function()
		local live: { [string]: boolean } = {}
		for _, entry in list do
			live[bare(entry.Emoji)] = true
		end
		for _, loser in { "🏙️", "📔", "📕", "📭", "💌", "🔄" } do
			assert(Icons.RETIRED[loser], loser .. " is not retired")
		end
		for retired, winner in Icons.RETIRED do
			assert(not live[bare(retired)], retired .. " is retired but still in the dictionary")
			local role, name = string.match(winner, "^(%a+)%.(%a+)$")
			assert(role and type(Icons[role]) == "table" and Icons[role][name], retired .. " -> " .. winner .. "?")
		end
		expect(Icons.RETIRED["🏙️"]).toBe("Unit.Level")
		expect(Icons.RETIRED["📭"]).toBe("Door.Mail")
		expect(Icons.RETIRED["🔄"]).toBe("Mark.Again")
	end)

	test("a Unit is glued in front of its number: one emoji, one space, the number", function()
		expect(Icons.unit("Cash", 300)).toBe("💰 300")
		expect(Icons.unit("Cash", "1.2K")).toBe("💰 1.2K")
		expect(Icons.unit("Stars", 5)).toBe("⭐ 5")
		expect(Icons.unit("Tree", 2)).toBe("🌳 2")
		expect(Icons.unit("Gems", 9)).toBe("9") -- no such unit: the number alone, never a made-up emoji
		for kind in Icons.Unit do
			expect(Icons.count(Icons.unit(kind, 1))).toBe(1)
		end
	end)

	test("the level badge and the gate note: one wording everywhere", function()
		expect(Icons.level(1)).toBe("🏥 Lv 1")
		expect(Icons.level(1, "Clinic")).toBe("🏥 Lv 1 Clinic")
		expect(Icons.level(3, "")).toBe("🏥 Lv 3")
		expect(Icons.needs(3)).toBe("Needs 🏥 Lv 3")
		expect(Icons.count(Icons.level(5, "City Hospital"))).toBe(1)
		expect(UiRules.calmText('local a = "' .. Icons.level(1, "Clinic") .. '"', "src/client/UI/Icons.luau")).toEqual({})
	end)

	test("the dictionary is frozen: a panel can't add or change an icon", function()
		for _, role in Icons.ROLES do
			expect(table.isfrozen(Icons[role])).toBe(true)
		end
		expect(table.isfrozen(Icons)).toBe(true)
		expect(table.isfrozen(Icons.RETIRED)).toBe(true)
	end)
end)

T.describe("Emoji in the chrome's own files", function()
	test("Kit, Modal and Theme type no emoji: the chrome reads UI/Icons", function()
		for _, name in { "Kit", "Modal", "Theme" } do
			local path = "src/client/UI/" .. name .. ".luau"
			local n = 0
			for line in string.gmatch(source(path) .. "\n", "(.-)\r?\n") do
				n += 1
				if not string.match(line, "^%s*%-%-") then
					for _, literal in UiRules.literals(line) do
						assert(Icons.count(literal.Text) == 0, path .. ":" .. n .. " types " .. literal.Text)
					end
				end
			end
		end
		assert(string.find(source("src/client/UI/Modal.luau"), "Text = Icons.Mark.Close", 1, true), "the ✖ is Icons'")
	end)

	test("a title is words only at run time too: Kit.panel and Modal.setTitle pass it through Icons.words", function()
		assert(string.find(source("src/client/UI/Kit.luau"), "Text = Icons.words(props.Title)", 1, true), "Kit.panel")
		assert(string.find(source("src/client/UI/Modal.luau"), "title.Text = Icons.words(text)", 1, true), "setTitle")
	end)
end)

T.describe("Pure.TEXT tables: at most one emoji per entry (a ratchet)", function()
	-- How many crowded TEXT entries each file may still have (a file not listed: 0). Numbers only go DOWN: the
	-- task that owns the file lowers it as it rebuilds the panel.
	-- Counted 2026-11-17: every file is at 0 already, so the table is empty and stays empty.
	local RATCHET: { [string]: number } = {}

	test("the scan finds a crowded entry, and lets one emoji, a comment and an allowed line through", function()
		expect(Icons.count("💰⭐ ×")).toBe(2)
		local text = table.concat({
			"Pure.TEXT = table.freeze({",
			'\tTeam = "Team",',
			'\tJob = "🍩 Healer",',
			'\tBoth = "🍩🍪 x",',
			'\t-- Old = "🍩🍪",',
			'\tOdds = "🍩 Rare 🍪", -- uirules: allow LabelEmoji (an odds row)',
			"})",
			'local after = "🍩🍪"',
		}, "\n")
		local path = root .. "/tests/.emojirules-scan.luau"
		fs.writeFile(path, text)
		local ok, found = pcall(crowdedText, "tests/.emojirules-scan.luau")
		fs.removeFile(path)
		assert(ok, tostring(found))
		expect(found).toEqual({ "tests/.emojirules-scan.luau:4  🍩🍪 x" })
	end)

	test("no UI file has more crowded TEXT entries than its ratchet number", function()
		local over = {}
		for _, path in UI_FILES do
			local found = crowdedText(path)
			if #found > (RATCHET[path] or 0) then
				table.insert(over, path .. ": " .. #found .. " now, the ratchet allows " .. (RATCHET[path] or 0))
				for _, line in found do
					table.insert(over, "    " .. line)
				end
			end
		end
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
	end)

	test("the ratchet only names real UI files", function()
		for path, n in RATCHET do
			assert(table.find(UI_FILES, path), path .. " is not a UI file")
			assert(type(n) == "number" and n > 0 and n % 1 == 0, path .. ": drop the entry at 0")
		end
	end)
end)
