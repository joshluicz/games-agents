--!strict
-- Runs every tests/*.spec.luau with Lune. From game/:  lune run tests/run
-- Prints PASS/FAIL per test and the totals, and exits 1 if anything failed.

local fs = require("@lune/fs")
local process = require("@lune/process")

local T = require("./expect")

local function findTestsDir(): string?
	for _, candidate in { "tests", "game/tests", "." } do
		if fs.isDir(candidate) and fs.isFile(candidate .. "/expect.luau") then
			return candidate
		end
	end
	return nil
end

local dir = findTestsDir()
if not dir then
	print("Could not find the tests folder. Run from game/:  lune run tests/run")
	process.exit(1)
	return
end

local specs = {}
for _, name in fs.readDir(dir) do
	if string.sub(name, -10) == ".spec.luau" then
		table.insert(specs, string.sub(name, 1, -6)) -- drop ".luau"
	end
end
table.sort(specs)

local failed = 0
local passed = 0
for _, spec in specs do
	print("\n" .. spec)
	local before = #T.results
	-- Call require from a Luau function in this file, so "./" resolves next to run.luau.
	local ok, err = pcall(function()
		return require("./" .. spec)
	end)
	if not ok then
		failed += 1
		print("  FAIL  (could not load the spec)\n        " .. tostring(err))
	end
	for index = before + 1, #T.results do
		local result = T.results[index]
		if result.Ok then
			passed += 1
			print("  PASS  " .. result.Name)
		else
			failed += 1
			print("  FAIL  " .. result.Name .. "\n        " .. tostring(result.Error))
		end
	end
end

print(string.format("\n%d passed, %d failed, %d spec files", passed, failed, #specs))
if failed > 0 then
	process.exit(1)
end
