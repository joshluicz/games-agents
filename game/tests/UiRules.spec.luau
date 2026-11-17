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
-- THE CALM RULES AND THEIR RATCHET (docs/plan/2026-11-17-ui-direction.md §6; Joshua, memory-20261117-007): the six
-- calm rules (TitleEmoji, LabelEmoji, LeadEmoji, TypedEmoji, SpaceLiteral, StrokeBudget: tests/uirules) over every
-- src/client file, against RATCHET below. A NUMBER MAY ONLY GO DOWN. T1 to T5 rebuilt their panels to 0 on every
-- rule (a line that must break a rule on purpose carries "-- uirules: allow <Rule>" and a reason) and the integrator
-- locked them there (REBUILT); the foundation's own files (Theme, Kit, Modal, Icons) are at 0 too. Only AdminPanel
-- and Feel/* still have a number. To see today's counts as a table ready to paste:
--     UIRULES_REPORT=1 lune run tests/run UiRules

local fs = require("@lune/fs")
local process = require("@lune/process")

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

-- THE RATCHET: how many calm-rule faults each file may still have. A file or a rule that isn't listed is 0. Numbers
-- only go DOWN (lower yours when you fix a file; never raise one, never add a line). Locked by the integrator on
-- 2026-11-17, AFTER T1 to T5 rebuilt their panels: every panel (NursePanel, Hud, Toasts, Wayfinder, Boards, Shop,
-- AgencyPanel, MarketPanel, BeltView, MiniGames, Tutorial, LiftPanel, Guide, SendCard, BranchPanel, BookPanel,
-- BadgeBook, Mailbox, PlayGifts, DayReportPanel, Celebrate) measured 0 on every rule, so none has a row and none may
-- get one. What is left is nobody's panel: the admin tools (never seen by players) and Feel/* (world bubbles and
-- signs, out of the calm UI's scope).
local RATCHET: { [string]: { [string]: number } } = {
	["src/client/Feel/CreatureProps.luau"] = { TypedEmoji = 1, StrokeBudget = 1 },
	["src/client/Feel/CureFX.luau"] = { LeadEmoji = 1, TypedEmoji = 11, StrokeBudget = 2 },
	["src/client/Feel/HospitalFX.luau"] = { StrokeBudget = 2 },
	["src/client/UI/AdminPanel.luau"] = { TitleEmoji = 7, LabelEmoji = 1, LeadEmoji = 8, TypedEmoji = 24 },
}

-- The rebuilt panels (T1 to T5): at 0 on every calm rule, with no ratchet row. Named here so a renamed or deleted
-- file can't slip out of the check unnoticed.
local REBUILT = {
	"NursePanel",
	"Hud",
	"Toasts",
	"Wayfinder",
	"Boards",
	"Shop",
	"AgencyPanel",
	"MarketPanel",
	"BeltView",
	"MiniGames",
	"Tutorial",
	"LiftPanel",
	"Guide",
	"SendCard",
	"BranchPanel",
	"BookPanel",
	"BadgeBook",
	"Mailbox",
	"PlayGifts",
	"DayReportPanel",
	"Celebrate",
}

-- The foundation's files: nothing left, and nothing may come back.
local FOUNDATION = {
	"src/client/UI/Theme.luau",
	"src/client/UI/Kit.luau",
	"src/client/UI/Modal.luau",
	"src/client/UI/Icons.luau",
}

T.describe("The calm rules over the whole client (the ratchet)", function()
	test("no file has more calm-rule faults than its ratchet number", function()
		local over, slack = UiRules.ratchet(CLIENT, RATCHET)
		if process.env.UIRULES_REPORT then
			print("\n-- today's calm-rule counts (paste over RATCHET's rows):\n" .. UiRules.table(CLIENT))
			if #slack > 0 then
				print("\n-- numbers that can come down:\n" .. table.concat(slack, "\n"))
			end
		end
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
	end)

	test("the ratchet only names real client files and real rules, with whole numbers above 0", function()
		for path, limits in RATCHET do
			assert(table.find(CLIENT, path), path .. " is not a src/client file")
			for rule, n in limits do
				assert(table.find(UiRules.CALM, rule), path .. ": " .. tostring(rule) .. " is not a calm rule")
				assert(type(n) == "number" and n > 0 and n % 1 == 0, path .. " " .. rule .. ": drop the entry at 0")
			end
		end
	end)

	test("the foundation is calm: Theme, Kit, Modal and Icons have nothing left and no ratchet entry", function()
		local found = UiRules.calm(FOUNDATION)
		assert(#found == 0, "\n" .. UiRules.format(found))
		for _, path in FOUNDATION do
			expect(RATCHET[path]).toBeNil()
		end
	end)

	test("the rebuilt panels stay at 0: every T1 to T5 file exists, has no ratchet row and no fault", function()
		local paths = {}
		for _, name in REBUILT do
			local path = "src/client/UI/" .. name .. ".luau"
			assert(table.find(CLIENT, path), path .. " is not a src/client file")
			expect(RATCHET[path]).toBeNil()
			table.insert(paths, path)
		end
		local found = UiRules.calm(paths)
		assert(#found == 0, "\n" .. UiRules.format(found))
	end)

	test("the ratchet never went up: no total is above the count the integrator locked", function()
		-- When the calm rules were written (2026-11-17, before T1 to T5) the totals were TitleEmoji 28, LabelEmoji 9,
		-- LeadEmoji 110, TypedEmoji 388, SpaceLiteral 8, StrokeBudget 102 (645). After the rebuild they are the
		-- numbers below (58): the ceiling now. A number here only ever goes down, with RATCHET.
		local CEILING = {
			TitleEmoji = 7,
			LabelEmoji = 1,
			LeadEmoji = 9,
			TypedEmoji = 36,
			SpaceLiteral = 0,
			StrokeBudget = 5,
		}
		local totals: { [string]: number } = {}
		for _, limits in RATCHET do
			for rule, n in limits do
				totals[rule] = (totals[rule] or 0) + n
			end
		end
		for _, rule in UiRules.CALM do
			local ceiling = CEILING[rule]
			assert(ceiling, rule .. " has no ceiling")
			assert(
				(totals[rule] or 0) <= ceiling,
				rule .. ": " .. (totals[rule] or 0) .. " is above the ceiling, " .. ceiling
			)
		end
		-- and the ratchet is exact today: nothing listed is slack (a fixed fault lowers its row in the same change)
		local _, slack = UiRules.ratchet(CLIENT, RATCHET)
		assert(#slack == 0, "\nlower these rows:\n" .. table.concat(slack, "\n"))
	end)
end)

T.describe("tests/uirules: the calm rules themselves", function()
	local function rules(text: string, path: string?): { string }
		local out = {}
		for _, violation in UiRules.calmText(text, path or "x.luau") do
			table.insert(out, violation.Rule)
		end
		return out
	end
	local Icons = UiRules.Icons

	test("the emoji reader: one entry per drawn emoji (a joined family is one), text symbols are not emoji", function()
		expect(Icons.count("Team")).toBe(0)
		expect(Icons.count("💰 300")).toBe(1)
		expect(Icons.count("👩‍⚕️ Team")).toBe(1) -- woman + joiner + staff: one picture
		expect(Icons.count("💰⭐ ×")).toBe(2)
		expect(Icons.count("🏡 🔑 💛")).toBe(3)
		expect(Icons.count("⚙️ and ⚙")).toBe(2)
		expect(Icons.count("↕️ Lift")).toBe(1)
		expect(Icons.count("A → B · C × 2 … ● •")).toBe(0)
		expect(Icons.clusters("🩺 Healer (🧪 at 🏥 Lv 2)")).toEqual({ "🩺", "🧪", "🏥" })
		expect(Icons.words("👩‍⚕️ Team")).toBe("Team")
		expect(Icons.words("Sell 💰 now")).toBe("Sell now")
		expect(Icons.words("⚙️ Settings")).toBe("Settings")
		expect(Icons.words("Day done!")).toBe("Day done!")
		expect(Icons.words("🎉")).toBe("")
	end)

	test("TitleEmoji: a title is words only", function()
		expect(rules('\tTitle = "Shop",')).toEqual({})
		expect(rules('\tTitle = "🍩 Snacks",')).toEqual({ "TitleEmoji" })
		expect(rules('\tResetTitle = "🍩 Reset tree?",')).toEqual({ "TitleEmoji" })
		expect(rules('modal.setTitle("🍩 Listen!")')).toEqual({ "TitleEmoji" })
		expect(rules("modal.setTitle(look.Title)")).toEqual({})
		expect(rules('\tSubtitle = "x", Icon = "🍩",')).toEqual({})
	end)

	test("LabelEmoji: one emoji per string, never two side by side", function()
		expect(rules('local a = "🍩🍪 ×"')).toEqual({ "LabelEmoji" })
		expect(rules('local a = "🍩 🍪 🍫"')).toEqual({ "LabelEmoji" })
		expect(rules('local a = "🍩 Healer"')).toEqual({})
		expect(rules('local a, b = "🍩", "🍪"')).toEqual({}) -- two strings, one each
		expect(rules('local a = "🍩 Rare 20% 🍪" -- uirules: allow LabelEmoji (an odds row)')).toEqual({})
	end)

	test(
		"LeadEmoji: no gesture, face, tick or party emoji in front of words; no emoji in front of a sentence",
		function()
			for _, text in
				{
					"👆 Tap a card",
					"👇 Pick one",
					"✋ Hold to sell",
					"👀 Which one fits?",
					"🎉 Yay!",
					"😊 Nice",
				}
			do
				expect(rules('local a = "' .. text .. '"')).toEqual({ "LeadEmoji" })
			end
			expect(rules('local a = "✨ The shiny one!"')).toEqual({ "LeadEmoji" })
			expect(rules('local a = "🍩 Listed nurses keep working"')).toEqual({ "LeadEmoji" }) -- any emoji, a sentence
			expect(rules('local a = "🍩 Healer"')).toEqual({}) -- an Art noun with its name
			expect(rules('local a = "🍩 Bath Room"')).toEqual({})
			expect(rules('local a = "🍩 300"')).toEqual({}) -- a Unit with its number
			expect(rules('local a = "🍩 Lv 1 Clinic"')).toEqual({})
			expect(rules('local a = "🎉"')).toEqual({}) -- alone: an art tile or a badge
			expect(rules('local a = "Pick the shiny one"')).toEqual({})
			expect(rules('local a = "Needs 🍩 Lv 3"')).toEqual({}) -- not in front
		end
	)

	test("TypedEmoji: a chrome emoji comes from UI/Icons, never typed (retired ones too); Icons itself may", function()
		expect(rules('local a = "💰 " .. cash')).toEqual({ "TypedEmoji" })
		expect(rules('local a = "Needs 🏥 Lv " .. level')).toEqual({ "TypedEmoji" })
		expect(rules('local a = "🔒"')).toEqual({ "TypedEmoji" })
		expect(rules('local a = "⚙"')).toEqual({ "TypedEmoji" }) -- with or without the picture selector
		expect(rules('local a = "Need 🏙️ Lv "')).toEqual({ "TypedEmoji" }) -- retired: 🏥 won
		expect(rules('local a = "📔"')).toEqual({ "TypedEmoji" })
		expect(rules('local a = Icons.Unit.Cash .. " " .. cash')).toEqual({})
		expect(rules('local a = "🧼"')).toEqual({}) -- Art: not a chrome emoji
		expect(rules('local a = "🎊"')).toEqual({}) -- Party is free where it belongs
		expect(rules('\tCash = "💰",', "src/client/UI/Icons.luau")).toEqual({})
		expect(rules('local a = "💰" -- uirules: allow TypedEmoji (a test string)')).toEqual({})
	end)

	test("SpaceLiteral: Kit.pad and Kit.list take Theme.Space.Step values only", function()
		expect(rules("Kit.pad(card, 12)")).toEqual({})
		expect(rules("Kit.pad(card, 0)")).toEqual({})
		expect(rules("Kit.pad(card, 10)")).toEqual({ "SpaceLiteral" })
		expect(rules("Kit.pad(card, 6)")).toEqual({ "SpaceLiteral" })
		expect(rules("Kit.pad(card, Theme.Space.PadCard)")).toEqual({})
		expect(rules("Kit.list(row, Enum.FillDirection.Horizontal, 2)")).toEqual({ "SpaceLiteral" })
		expect(rules("Kit.list(row, Enum.FillDirection.Horizontal, 8)")).toEqual({})
		expect(rules("Kit.list(row, Enum.FillDirection.Horizontal, Theme.Space.Tight)")).toEqual({})
		expect(rules("Kit.list(row)")).toEqual({})
		for step in UiRules.STEP do
			expect(rules("Kit.pad(card, " .. step .. ")")).toEqual({})
		end
	end)

	test("StrokeBudget: every shape outline counts, Kit.stroke or a hand-made UIStroke; text outlines don't", function()
		expect(rules("Kit.stroke(card, Theme.Colors.CardLine, Theme.Stroke.Fine)")).toEqual({ "StrokeBudget" })
		expect(rules('local stroke = Instance.new("UIStroke")')).toEqual({ "StrokeBudget" })
		expect(rules("Kit.outline(label)")).toEqual({})
		expect(rules("Kit.stroke(plate) -- uirules: allow StrokeBudget (a HUD plate over the world)")).toEqual({})
		expect(rules("-- Kit.stroke(card)")).toEqual({})
	end)

	test("tally, ratchet and table: over the limit fails with its lines, under it is slack", function()
		local found = UiRules.calmText('local a = "👆 Tap"\nKit.pad(x, 6)\nKit.pad(y, 10)\n', "p.luau")
		expect(UiRules.tally(found)).toEqual({ ["p.luau"] = { LeadEmoji = 1, SpaceLiteral = 2 } })
		expect(found[2].Line).toBe(2)
		local over, slack = UiRules.ratchet(FOUNDATION, { ["src/client/UI/Kit.luau"] = { StrokeBudget = 3 } })
		expect(over).toEqual({})
		expect(slack).toEqual({ "src/client/UI/Kit.luau  StrokeBudget  3 -> 0" })
		expect(UiRules.table(FOUNDATION)).toBe("")
	end)

	test("the Step the rule checks is Theme's own", function()
		local theme = fs.readFile(root .. "/src/client/UI/Theme.luau")
		local steps = string.match(theme, "Step = table%.freeze%({ ([%d, ]+) }%)")
		assert(steps, "Theme.Space.Step not found")
		local seen = 0
		for step in string.gmatch(steps, "%d+") do
			seen += 1
			assert(UiRules.STEP[tonumber(step)], "Theme step " .. step .. " is not in UiRules.STEP")
		end
		expect(seen).toBe(6)
	end)
end)

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
