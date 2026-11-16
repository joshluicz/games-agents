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

function UiRules.checkText(text: string, path: string?): { any }
	local out = {}
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
		local body = code(line)
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
	end
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

function UiRules.format(violations: { any }): string
	local lines = {}
	for _, v in violations do
		table.insert(lines, string.format("%s:%d  %s  %s", v.Path, v.Line, v.Rule, v.Text))
	end
	return table.concat(lines, "\n")
end

return UiRules
