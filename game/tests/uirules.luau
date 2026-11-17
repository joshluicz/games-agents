--!nocheck
-- The UI rules every panel file follows, checked on the shipped source text (not a spec itself; look build plan §B8
-- and §D Task 0). Each UI task's spec calls it on the files it owns; the integrator's UiRules.spec runs it over
-- every src/client file.
--
--   UiRules.check(paths): { Violation }           paths are repo paths ("src/client/UI/Shop.luau")
--   UiRules.checkText(text, path?): { Violation } the same on a string (for the helper's own tests)
--   UiRules.format(violations): string            one line each: "path:line  Rule  text"
--   Violation = { Path: string, Line: number, Rule: string, Text: string }
--
-- The rules (comments are ignored):
--   MinTextSize    a UITextSizeConstraint MinTextSize (or MaxTextSize) set to a number under 18: text would shrink
--                  below the floor. Use Kit.textLimit
--   TextSize       a literal TextSize under 18. Use Theme.TextSize (Caption = 18 is the floor)
--   LocalHelper    a local copy of paintTab or textLimit. Use Kit.tab and Kit.textLimit
--   CornerLiteral  a corner radius written as a number: CornerRadius = UDim.new(0, n) or Kit.corner(x, n). Use
--                  Theme.Radius
--   HeaderColor    a panel-specific header colour: a modal spec's `Accent = ...` or a local ACCENT. Every header is
--                  Theme.Colors.Header (navy)
-- A line that must break a rule on purpose ends with the comment "-- uirules: allow <Rule>".
--
-- THE CALM RULES (UI direction §6; Joshua, memory-20261117-007: a calm UI, emoji used correctly). They are checked
-- apart from the rules above because the panels are being rebuilt one task at a time: each file has a RATCHET (how
-- many of each it may still have, written in tests/UiRules.spec.luau) that may only go down, until it is 0.
--
--   UiRules.CALM                                  the six rule names, in order
--   UiRules.calm(paths): { Violation }            the calm rules over shipped files
--   UiRules.calmText(text, path?): { Violation }  the same on a string
--   UiRules.tally(violations)                     { [path] = { [rule] = count } }
--   UiRules.ratchet(paths, limits)                (over, slack): two lists of lines. `limits` is { [path] = { [rule]
--                                                 = n } } (a missing file or rule is 0). `over` = a file has MORE
--                                                 than its limit (a failure) · `slack` = it has fewer (lower the
--                                                 number in the spec)
--   UiRules.table(paths)                          the ratchet table as Luau source, with today's counts (paste it
--                                                 into UiRules.spec.luau)
--   UiRules.literals(line): { { Text, At } }      the string literals on one line of code (At = the opening quote)
--   UiRules.Icons                                 src/client/UI/Icons.luau, loaded (clusters, count, words ...)
--
--   TitleEmoji     a title with an emoji: `Title = "🛒 Shop"` (any ...Title key) or `setTitle("🛒 Shop")`. A panel
--                  title is words only
--   LabelEmoji     one string literal with more than one emoji ("💰⭐ ×", "🏡 🔑 💛"). The listed exceptions (an odds
--                  row, a tutorial pointer) carry the allow comment
--   LeadEmoji      a literal that OPENS with an emoji used as a bullet: a gesture, a face, a tick or a party emoji
--                  in front of words ("👆 Tap a card", "✅ You keep", "🎉 Yay!"), or any emoji in front of a sentence
--                  (three words or more: "💼 Listed nurses keep working"). A literal that is only the emoji is fine
--                  (an art tile, a State badge), and so is a Unit with its number or an Art noun with its name
--                  ("💰 300", "🩺 Healer")
--   TypedEmoji     a chrome emoji typed into a UI file instead of read from UI/Icons.luau: any Door, Unit, State,
--                  Status or Mark emoji, or a retired one (Icons.RETIRED). UI/Icons.luau itself is exempt
--   SpaceLiteral   a number passed to Kit.pad or Kit.list that isn't in Theme.Space.Step (4, 8, 12, 16, 24, 32; 0
--                  is fine). Use Theme.Space
--   StrokeBudget   a shape outline: `Kit.stroke(` or `Instance.new("UIStroke")`. The dark outline is for the panel
--                  shell, candy buttons, HUD plates over the 3D world and text over the world or over colour
--                  (R2); those lines carry the allow comment, the rest go

local fs = require("@lune/fs")

local UiRules = {}

UiRules.FLOOR = 18

local function find(relative: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. relative) then
			return prefix .. relative
		end
	end
	error("can't find " .. relative .. " (run from game/)")
end

-- The code part of a line: everything before a `--` comment that isn't inside a string.
local function code(line: string): string
	local quote: string? = nil
	local i = 1
	while i <= #line do
		local c = string.sub(line, i, i)
		if quote then
			if c == "\\" then
				i += 1
			elseif c == quote then
				quote = nil
			end
		elseif c == '"' or c == "'" or c == "`" then
			quote = c
		elseif c == "-" and string.sub(line, i + 1, i + 1) == "-" then
			return string.sub(line, 1, i - 1)
		end
		i += 1
	end
	return line
end

local function allowed(line: string, rule: string): boolean
	return string.find(line, "uirules: allow " .. rule, 1, true) ~= nil
end

-- The string literals on one line of code ("...", '...' or `...`), outside a `--` comment.
function UiRules.literals(line: string): { { Text: string, At: number } }
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
				table.insert(out, { Text = string.sub(line, start + 1, i - 1), At = start })
				quote = nil
			end
		elseif c == '"' or c == "'" or c == "`" then
			quote = c
			start = i
		elseif c == "-" and string.sub(line, i + 1, i + 1) == "-" then
			break
		end
		i += 1
	end
	return out
end

-- Calls fn(line, body, lineNumber) for every line that isn't inside a block comment (body = the line's code).
local function eachLine(text: string, fn: (line: string, body: string, lineNumber: number) -> ())
	local lineNumber = 0
	local inBlockComment = false
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		lineNumber += 1
		if inBlockComment then
			if string.find(line, "]]", 1, true) then
				inBlockComment = false
			end
			continue
		end
		if string.find(line, "^%s*%-%-%[%[") and not string.find(line, "]]", 1, true) then
			inBlockComment = true
			continue
		end
		fn(line, code(line), lineNumber)
	end
end

function UiRules.checkText(text: string, path: string?): { any }
	local out = {}
	eachLine(text, function(line: string, body: string, lineNumber: number)
		local function report(rule: string)
			if not allowed(line, rule) then
				table.insert(out, {
					Path = path or "?",
					Line = lineNumber,
					Rule = rule,
					Text = (string.gsub(body, "^%s+", "")),
				})
			end
		end

		for kind, value in string.gmatch(body, "%f[%w](M[ia][nx])TextSize%s*=%s*(%d+%.?%d*)") do
			local _ = kind
			if (tonumber(value) :: number) < UiRules.FLOOR then
				report("MinTextSize")
			end
		end
		for prefix, value in string.gmatch(body, "([%w_]*)TextSize%s*=%s*(%d+%.?%d*)%f[^%d%.]") do
			if prefix ~= "Min" and prefix ~= "Max" and (tonumber(value) :: number) < UiRules.FLOOR then
				report("TextSize")
			end
		end
		if
			string.find(body, "local%s+function%s+paintTab%f[^%w_]")
			or string.find(body, "local%s+function%s+textLimit%f[^%w_]")
			or string.find(body, "local%s+paintTab%s*=")
			or string.find(body, "local%s+textLimit%s*=")
		then
			report("LocalHelper")
		end
		if
			string.find(body, "CornerRadius%s*=%s*UDim%.new%(%s*0%s*,%s*%d")
			or string.find(body, "Kit%.corner%(%s*[^,%)]+,%s*%d")
		then
			report("CornerLiteral")
		end
		if string.find(body, "%f[%w_]Accent%s*=%s*[^=]") or string.find(body, "local%s+ACCENT%f[^%w_]") then
			report("HeaderColor")
		end
	end)
	return out
end

function UiRules.check(paths: { string }): { any }
	local out = {}
	for _, path in paths do
		for _, violation in UiRules.checkText(fs.readFile(find(path)), path) do
			table.insert(out, violation)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- The calm rules
------------------------------------------------------------------------------------------------------------------

local luau = require("@lune/luau")

UiRules.CALM = { "TitleEmoji", "LabelEmoji", "LeadEmoji", "TypedEmoji", "SpaceLiteral", "StrokeBudget" }
UiRules.STEP = { [0] = true, [4] = true, [8] = true, [12] = true, [16] = true, [24] = true, [32] = true }

local ICONS_PATH = "src/client/UI/Icons.luau"
local Icons = luau.load(fs.readFile(find(ICONS_PATH)), { debugName = "Icons" })()
UiRules.Icons = Icons

-- An emoji without its picture selector, so "⚙" and "⚙️" are the same one.
local function bare(emoji: string): string
	return (string.gsub(emoji, "\u{FE0F}", ""))
end

-- Every chrome emoji a panel must read from Icons (Party is free: Celebrate and reward toasts stay loud).
local CHROME: { [string]: string } = {}
for _, entry in Icons.list() do
	if entry.Role ~= "Party" then
		CHROME[bare(entry.Emoji)] = entry.Role .. "." .. entry.Name
	end
end
for emoji, winner in Icons.RETIRED do
	CHROME[bare(emoji)] = winner
end

-- Emoji that are bullets, never nouns: gestures, ticks and party (faces are found by range).
local LEAD: { [string]: boolean } = {}
for _, emoji in
	{
		"👆",
		"👇",
		"👈",
		"👉",
		"☝️",
		"✋",
		"👋",
		"👍",
		"👎",
		"👏",
		"🙌",
		"🤝",
		"🙏",
		"💪",
		"👀",
		"✅",
		"✔️",
		"☑️",
		"✓",
		"🎉",
		"🎊",
		"✨",
		"🥳",
		"🎈",
		"🔥",
		"💥",
		"💫",
	}
do
	LEAD[bare(emoji)] = true
end

local function isFace(emoji: string): boolean
	local cp = utf8.codepoint(emoji, 1)
	return (cp >= 0x1F600 and cp <= 0x1F64F) or (cp >= 0x1F910 and cp <= 0x1F92F) or (cp >= 0x1F970 and cp <= 0x1F97A)
end

-- How many words (two letters or more) a text has.
local function wordCount(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%a%a+") do
		n += 1
	end
	return n
end

function UiRules.calmText(text: string, path: string?): { any }
	local out = {}
	local isIcons = path ~= nil and string.sub(path, -#ICONS_PATH) == ICONS_PATH
	eachLine(text, function(line: string, body: string, lineNumber: number)
		local function report(rule: string)
			if not allowed(line, rule) then
				table.insert(out, {
					Path = path or "?",
					Line = lineNumber,
					Rule = rule,
					Text = (string.gsub(body, "^%s+", "")),
				})
			end
		end

		for _, literal in UiRules.literals(body) do
			local clusters = Icons.clusters(literal.Text)
			if #clusters == 0 then
				continue
			end
			local before = string.sub(body, 1, literal.At - 1)
			if string.find(before, "Title%s*=%s*$") or string.find(before, "setTitle%(%s*$") then
				report("TitleEmoji")
			end
			if #clusters > 1 then
				report("LabelEmoji")
			end
			local first = clusters[1]
			local opening = string.gsub(literal.Text, "^%s+", "")
			if string.sub(opening, 1, #first) == first then
				local rest = Icons.words(string.sub(opening, #first + 1))
				if rest ~= "" and (LEAD[bare(first)] or isFace(first) or wordCount(rest) >= 3) then
					report("LeadEmoji")
				end
			end
			if not isIcons then
				for _, emoji in clusters do
					if CHROME[bare(emoji)] then
						report("TypedEmoji")
					end
				end
			end
		end

		for value in string.gmatch(body, "Kit%.pad%(%s*[^,%)]+,%s*(%d+%.?%d*)%s*%)") do
			if not UiRules.STEP[tonumber(value) :: number] then
				report("SpaceLiteral")
			end
		end
		for value in string.gmatch(body, "Kit%.list%(%s*[^,%)]+,[^,%)]+,%s*(%d+%.?%d*)%s*%)") do
			if not UiRules.STEP[tonumber(value) :: number] then
				report("SpaceLiteral")
			end
		end

		for _ in string.gmatch(body, "Kit%.stroke%(") do
			report("StrokeBudget")
		end
		for _ in string.gmatch(body, 'Instance%.new%(%s*"UIStroke"') do
			report("StrokeBudget")
		end
	end)
	return out
end

function UiRules.calm(paths: { string }): { any }
	local out = {}
	for _, path in paths do
		for _, violation in UiRules.calmText(fs.readFile(find(path)), path) do
			table.insert(out, violation)
		end
	end
	return out
end

function UiRules.tally(violations: { any }): { [string]: { [string]: number } }
	local counts = {}
	for _, v in violations do
		counts[v.Path] = counts[v.Path] or {}
		counts[v.Path][v.Rule] = (counts[v.Path][v.Rule] or 0) + 1
	end
	return counts
end

-- The ratchet: `over` lists every file and rule with MORE violations than its limit (with the lines), `slack` every
-- one with fewer (the number in the spec should come down to it).
function UiRules.ratchet(paths: { string }, limits: { [string]: { [string]: number } }): ({ string }, { string })
	local violations = UiRules.calm(paths)
	local counts = UiRules.tally(violations)
	local over, slack = {}, {}
	for _, path in paths do
		for _, rule in UiRules.CALM do
			local have = (counts[path] or {})[rule] or 0
			local limit = (limits[path] or {})[rule] or 0
			if have > limit then
				table.insert(over, string.format("%s  %s  %d now, the ratchet allows %d", path, rule, have, limit))
				for _, v in violations do
					if v.Path == path and v.Rule == rule then
						table.insert(over, string.format("    %s:%d  %s", v.Path, v.Line, v.Text))
					end
				end
			elseif have < limit then
				table.insert(slack, string.format("%s  %s  %d -> %d", path, rule, limit, have))
			end
		end
	end
	return over, slack
end

-- The ratchet table as Luau source with today's counts (files with nothing left are not listed).
function UiRules.table(paths: { string }): string
	local counts = UiRules.tally(UiRules.calm(paths))
	local lines = {}
	for _, path in paths do
		local parts = {}
		for _, rule in UiRules.CALM do
			local n = (counts[path] or {})[rule] or 0
			if n > 0 then
				table.insert(parts, rule .. " = " .. n)
			end
		end
		if #parts > 0 then
			table.insert(lines, string.format('\t["%s"] = { %s },', path, table.concat(parts, ", ")))
		end
	end
	return table.concat(lines, "\n")
end

function UiRules.format(violations: { any }): string
	local lines = {}
	for _, v in violations do
		table.insert(lines, string.format("%s:%d  %s  %s", v.Path, v.Line, v.Rule, v.Text))
	end
	return table.concat(lines, "\n")
end

return UiRules
