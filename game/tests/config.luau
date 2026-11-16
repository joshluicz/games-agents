--!strict
-- The real Shared/Config, loaded in Lune for the specs (not a spec itself). Config's only Roblox type is Vector3, so
-- a stub stands in for Vector3.new and gives a frozen { X, Y, Z } table. Specs that check shipped numbers (the belt's
-- odds and placement, the line length) use this instead of copying them, so a spec can't pass on stale copies.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function find(relative: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. relative) then
			return prefix .. relative
		end
	end
	error("could not find " .. relative)
end

local Vector3Stub = {
	new = function(x: number?, y: number?, z: number?)
		return table.freeze({ X = x or 0, Y = y or 0, Z = z or 0 })
	end,
}

local path = find("src/shared/Config.luau")
local chunk = luau.load(fs.readFile(path), {
	debugName = path,
	environment = { Vector3 = Vector3Stub },
	injectGlobals = true,
})

return chunk() :: any
