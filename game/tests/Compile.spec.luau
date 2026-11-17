--!nocheck
-- Every src file compiles (Real Clinic review fixes). Luau gives a chunk 200 local registers and a module with more
-- top-level locals than that does not compile at all ("Out of local registers"): in the game the whole module, and
-- everything that requires it, then fails to load. The other specs load only PURE blocks and mocked pieces, so only
-- this one sees it. Checked at every optimisation and debug level, because a constant local costs no register at
-- O1+ with debug level 1 but does with full debug info (Studio).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")

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

T.describe("Every src file compiles", function()
	test("no syntax error and no chunk out of local registers, at every optimisation and debug level", function()
		expect(#files > 100).toBe(true)
		local broken: { string } = {}
		for _, path in files do
			local source = fs.readFile(path)
			for _, debugLevel in { 1, 2 } do
				for _, optimizationLevel in { 0, 1, 2 } do
					local ok, err =
						pcall(luau.compile, source, { optimizationLevel = optimizationLevel, debugLevel = debugLevel })
					if not ok then
						table.insert(
							broken,
							string.format("%s (O%d g%d): %s", path, optimizationLevel, debugLevel, tostring(err))
						)
					end
				end
			end
		end
		expect(broken).toEqual({})
	end)
end)
