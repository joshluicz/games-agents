--!strict
-- A tiny test kit for Lune specs. Run every spec from game/ with:  lune run tests/run
--
--   local T = require("./expect")
--   local expect, test = T.expect, T.test
--   local Schema = require("../src/shared/Logic/Schema")
--
--   T.describe("Schema", function()
--       test("default has Version 2", function()
--           expect(Schema.default().Version).toBe(2)
--       end)
--   end)
--
-- Matchers: toBe (==), toEqual (deep), toBeTruthy, toBeFalsy, toBeNil, toBeCloseTo(n, digits?).
-- Specs may only require pure modules (Logic/* and the Lune-safe Data/* files), never Roblox services.

export type Result = { Name: string, Ok: boolean, Error: string? }

local T = {}

T.results = {} :: { Result }
local prefix: { string } = {}

local function show(value: any, depth: number?): string
	local level = depth or 0
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	if level > 3 then
		return "{...}"
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in keys do
		table.insert(parts, tostring(key) .. " = " .. show(value[key], level + 1))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end
T.show = show

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end
T.deepEqual = deepEqual

function T.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			error("expected " .. show(expected) .. ", got " .. show(actual), 2)
		end
	end

	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error("expected (deep) " .. show(expected) .. ",\n        got " .. show(actual), 2)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error("expected a truthy value, got " .. show(actual), 2)
		end
	end

	function matchers.toBeFalsy()
		if actual then
			error("expected a falsy value, got " .. show(actual), 2)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			error("expected nil, got " .. show(actual), 2)
		end
	end

	function matchers.toBeCloseTo(expected: number, digits: number?)
		local tolerance = 10 ^ -(digits or 4) / 2
		if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
			error("expected about " .. tostring(expected) .. ", got " .. show(actual), 2)
		end
	end

	return matchers
end

-- Runs the test now and records the result.
function T.test(name: string, fn: () -> ())
	local fullName = if #prefix > 0 then table.concat(prefix, " > ") .. " > " .. name else name
	local ok, err = pcall(fn)
	table.insert(T.results, { Name = fullName, Ok = ok, Error = if ok then nil else tostring(err) })
end

function T.describe(name: string, fn: () -> ())
	table.insert(prefix, name)
	local ok, err = pcall(fn)
	table.remove(prefix)
	if not ok then
		table.insert(T.results, { Name = name .. " (describe)", Ok = false, Error = tostring(err) })
	end
end

return T
