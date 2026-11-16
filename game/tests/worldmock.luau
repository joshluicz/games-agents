--!nocheck
-- A small Instance mock for building the REAL world modules under Lune (not a spec itself). Moved out of
-- Hospital.spec by the look overhaul's Foundation, so Hospital.spec, PartBudget.spec and the new world specs
-- (TownWorld, PlotWorld, Studs, Lighting ...) all build what ships the same way.
-- Datatypes (Vector3, CFrame, Color3, Enum ...) are Lune's own roblox ones; Instances are plain tables.
--
--   local World = require("./worldmock")
--   local world = World.new()                      a fresh, empty world (its own Workspace, tags and module cache)
--   world.load("src/server/PlotBuilder.luau")      the shipped module, its requires resolved from src/ the same way
--                                                  (script.Parent.X, ReplicatedStorage.Shared.X, :WaitForChild)
--   world.new(className)                           an Instance (also what Instance.new gives the loaded modules)
--   world.Workspace · world.ServerStorage · world.MaterialService      the service mocks (Folders)
--   world.tagged(tag): { Instance }                CollectionService:GetTagged
--   world.setVariant(on)                           THE STUDS SWITCH: adds (or removes) a MaterialVariant named
--                                                  Config.Look.StudsVariant in MaterialService, so World/Studs runs
--                                                  in "Variant" mode (default: "Surface"). It fires ChildAdded /
--                                                  ChildRemoved like Studio does
--   world.setNight(on)                             sets Workspace.IsNight and fires its changed signal
--   world.parts(root): { Instance }                every BasePart under root
--   world.box(part, pivot?): (lo, hi)              a part's bounding corners, in `pivot`'s space when given
--   World.find(relative): string                   a repo path from game/ or the repo root
--   World.roblox                                   Lune's roblox library
-- What the mock knows: Name, ClassName, Parent (with ChildAdded / ChildRemoved), children by name, attributes (with
-- GetAttributeChangedSignal), tags, IsA (BasePart, Light, GuiObject by class), Clone, Destroy, ClearAllChildren,
-- GetDescendants, FindFirstChild(WhichIsA/OfClass), FindFirstAncestor, IsDescendantOf, GetBoundingBox, GetPivot,
-- PivotTo. Any other property is just stored. Events it doesn't model (Triggered, Destroying, Touched ...) connect
-- to nothing.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local World = {}
World.roblox = roblox

function World.find(relative: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. relative) then
			return prefix .. relative
		end
	end
	error("can't find " .. relative .. " (run from game/)")
end

local BASE = {
	Part = true,
	WedgePart = true,
	CornerWedgePart = true,
	MeshPart = true,
	SpawnLocation = true,
	TrussPart = true,
	Seat = true,
}
local GUI_OBJECT = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	CanvasGroup = true,
}
local QUIET_EVENTS = {
	Destroying = true,
	Triggered = true,
	Touched = true,
	TouchEnded = true,
	Changed = true,
	AncestryChanged = true,
	PromptShown = true,
	PromptHidden = true,
	Activated = true,
}

function World.new()
	local world = {}
	local tags: { [string]: { any } } = {}
	local tagSignals: { [string]: any } = {}
	local methods = {}
	local meta = {}

	local function signal()
		local listeners = {}
		local self = {}
		function self:Connect(fn)
			local entry = { fn }
			table.insert(listeners, entry)
			return {
				Disconnect = function()
					local index = table.find(listeners, entry)
					if index then
						table.remove(listeners, index)
					end
				end,
			}
		end
		function self:Once(fn)
			local connection
			connection = self:Connect(function(...)
				connection.Disconnect()
				fn(...)
			end)
			return connection
		end
		function self:Fire(...)
			for _, entry in table.clone(listeners) do
				entry[1](...)
			end
		end
		return self
	end

	local function noSignal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
			Once = function()
				return { Disconnect = function() end }
			end,
		}
	end

	local function new(className: string)
		local p = { Name = className, ClassName = className, _children = {}, _attrs = {}, _signals = {} }
		if BASE[className] then
			p.Size, p.CFrame, p.CanCollide, p.CanQuery, p.Transparency =
				Vector3.new(4, 1, 2), CFrame.new(), true, true, 0
			p.Material = roblox.Enum.Material.Plastic
			p.Color = roblox.Color3.fromRGB(163, 162, 165)
			p.MaterialVariant = ""
			p.CastShadow = true
		end
		return setmetatable({ _p = p }, meta)
	end
	world.new = new

	local function eventOf(instance, name: string)
		local p = rawget(instance, "_p")
		local found = p._signals[name]
		if not found then
			found = signal()
			p._signals[name] = found
		end
		return found
	end

	function methods:IsA(class)
		local cn = rawget(self, "_p").ClassName
		return cn == class
			or class == "Instance"
			or (class == "BasePart" and BASE[cn] == true)
			or (class == "Light" and string.find(cn, "Light$") ~= nil)
			or (class == "GuiObject" and GUI_OBJECT[cn] == true)
			or (class == "GuiButton" and (cn == "TextButton" or cn == "ImageButton"))
			or (class == "LuaSourceContainer" and (cn == "Script" or cn == "LocalScript" or cn == "ModuleScript"))
	end
	function methods:GetChildren()
		return table.clone(rawget(self, "_p")._children)
	end
	function methods:GetDescendants()
		local out = {}
		local function walk(i)
			for _, c in rawget(i, "_p")._children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function methods:FindFirstChild(name, recursive)
		for _, c in rawget(self, "_p")._children do
			if c.Name == name then
				return c
			end
		end
		if recursive then
			for _, c in rawget(self, "_p")._children do
				local found = c:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function methods:WaitForChild(name)
		return self:FindFirstChild(name)
	end
	function methods:FindFirstChildWhichIsA(class, recursive)
		for _, d in (if recursive then self:GetDescendants() else self:GetChildren()) do
			if d:IsA(class) then
				return d
			end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(class)
		for _, c in self:GetChildren() do
			if c.ClassName == class then
				return c
			end
		end
		return nil
	end
	function methods:FindFirstAncestor(name)
		local p = self.Parent
		while p and p.Name ~= name do
			p = p.Parent
		end
		return p
	end
	function methods:IsDescendantOf(ancestor)
		local p = self.Parent
		while p do
			if p == ancestor then
				return true
			end
			p = p.Parent
		end
		return false
	end
	function methods:SetAttribute(k, v)
		local p = rawget(self, "_p")
		if p._attrs[k] ~= v then
			p._attrs[k] = v
			local changed = p._signals["Attribute:" .. k]
			if changed then
				changed:Fire()
			end
		end
	end
	function methods:GetAttribute(k)
		return rawget(self, "_p")._attrs[k]
	end
	function methods:GetAttributes()
		return table.clone(rawget(self, "_p")._attrs)
	end
	function methods:GetAttributeChangedSignal(k)
		return eventOf(self, "Attribute:" .. k)
	end
	function methods:GetPropertyChangedSignal()
		return noSignal()
	end
	function methods:Destroy()
		self.Parent = nil
	end
	local function addTag(instance, tag)
		tags[tag] = tags[tag] or {}
		if not table.find(tags[tag], instance) then
			table.insert(tags[tag], instance)
			if tagSignals[tag] then
				tagSignals[tag]:Fire(instance)
			end
		end
	end
	function methods:AddTag(tag)
		addTag(self, tag)
	end
	function methods:HasTag(tag)
		return tags[tag] ~= nil and table.find(tags[tag], self) ~= nil
	end
	function methods:Clone()
		local src = rawget(self, "_p")
		local copy = new(src.ClassName)
		local p = rawget(copy, "_p")
		for k, v in src do
			if k ~= "_children" and k ~= "_attrs" and k ~= "_signals" and k ~= "Parent" then
				p[k] = v
			end
		end
		for k, v in src._attrs do
			p._attrs[k] = v
		end
		for _, child in src._children do
			child:Clone().Parent = copy
		end
		return copy
	end
	function methods:ClearAllChildren()
		for _, c in self:GetChildren() do
			c:Destroy()
		end
	end
	local function boxOf(model)
		local lo, hi
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local cf, s = part.CFrame, part.Size / 2
				for _, c in { cf * Vector3.new(-s.X, -s.Y, -s.Z), cf * Vector3.new(s.X, s.Y, s.Z) } do
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		if not lo then
			return CFrame.new(), Vector3.zero
		end
		return CFrame.new((lo + hi) / 2), hi - lo
	end
	function methods:GetBoundingBox()
		return boxOf(self)
	end
	function methods:GetPivot()
		local p = rawget(self, "_p")
		if BASE[p.ClassName] then
			return p.CFrame
		end
		return if p.PrimaryPart then p.PrimaryPart.CFrame elseif p.WorldPivot then p.WorldPivot else (boxOf(self))
	end
	function methods:PivotTo(cf)
		local p = rawget(self, "_p")
		if BASE[p.ClassName] then
			p.CFrame = cf
			return
		end
		local offset = cf * self:GetPivot():Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = offset * d.CFrame
			end
		end
		if p.WorldPivot then
			p.WorldPivot = offset * p.WorldPivot
		end
	end
	meta.__index = function(self, k)
		local p = rawget(self, "_p")
		if k == "Position" and p.CFrame then
			return p.CFrame.Position
		end
		if p[k] ~= nil then
			return p[k]
		end
		if methods[k] then
			return methods[k]
		end
		if k == "ChildAdded" or k == "ChildRemoved" then
			return eventOf(self, k)
		end
		if QUIET_EVENTS[k] then
			return noSignal()
		end
		return self:FindFirstChild(k)
	end
	meta.__newindex = function(self, k, v)
		local p = rawget(self, "_p")
		if k == "Parent" then
			local old = p.Parent
			if old == v then
				return
			end
			if old then
				local list = rawget(old, "_p")._children
				table.remove(list, table.find(list, self))
			end
			p.Parent = v
			if v then
				table.insert(rawget(v, "_p")._children, self)
			end
			if old and rawget(old, "_p")._signals.ChildRemoved then
				rawget(old, "_p")._signals.ChildRemoved:Fire(self)
			end
			if v and rawget(v, "_p")._signals.ChildAdded then
				rawget(v, "_p")._signals.ChildAdded:Fire(self)
			end
		else
			p[k] = v
		end
	end

	local function service(name: string)
		local folder = new("Folder")
		folder.Name = name
		return folder
	end
	local workspaceMock = service("Workspace")
	rawset(rawget(workspaceMock, "_p"), "GetServerTimeNow", function()
		return 0
	end)
	local storageMock = service("ServerStorage")
	local materialsMock = service("MaterialService")
	world.Workspace = workspaceMock
	world.ServerStorage = storageMock
	world.MaterialService = materialsMock

	local services = {
		Workspace = workspaceMock,
		ServerStorage = storageMock,
		MaterialService = materialsMock,
		CollectionService = {
			AddTag = function(_, instance, tag)
				addTag(instance, tag)
			end,
			HasTag = function(_, instance, tag)
				return instance:HasTag(tag)
			end,
			GetTagged = function(_, tag)
				return table.clone(tags[tag] or {})
			end,
			GetInstanceAddedSignal = function(_, tag)
				tagSignals[tag] = tagSignals[tag] or signal()
				return tagSignals[tag]
			end,
			GetInstanceRemovedSignal = noSignal,
		},
	}

	function world.tagged(tag: string)
		return table.clone(tags[tag] or {})
	end

	-- A path that stands in for a ModuleScript: script.Parent.World.Parts, Shared.Logic:WaitForChild("Tutorial") ...
	local function ref(path: string)
		return setmetatable({ _path = path }, {
			__index = function(_, k)
				if k == "Parent" then
					return ref((string.match(path, "^(.*)/[^/]+$")))
				elseif k == "WaitForChild" or k == "FindFirstChild" then
					return function(self, name)
						return self[name]
					end
				end
				return ref(path .. "/" .. k)
			end,
		})
	end
	local replicated = setmetatable({}, {
		__index = function(_, k)
			if k == "WaitForChild" or k == "FindFirstChild" then
				return function(self, name)
					return self[name]
				end
			elseif k == "Shared" then
				return ref("src/shared")
			end
			return nil
		end,
	})

	local loaded = {}
	local function load(path: string): any
		if loaded[path] ~= nil then
			return loaded[path]
		end
		local env = {
			game = {
				GetService = function(_, name)
					return if name == "ReplicatedStorage" then replicated else services[name]
				end,
			},
			script = ref((string.gsub(path, "%.luau$", ""))),
			require = function(r)
				return load(r._path .. ".luau")
			end,
			Instance = { new = new },
			TweenInfo = {
				new = function(...)
					return { ... }
				end,
			},
			task = task,
			warn = function() end,
			typeof = function(value)
				if type(value) == "table" and getmetatable(value) == meta then
					return "Instance"
				end
				return typeof(value)
			end,
		}
		for k, v in roblox do
			if env[k] == nil and k ~= "Instance" then
				env[k] = v
			end
		end
		local result = luau.load(fs.readFile(World.find(path)), { debugName = path, environment = env })()
		loaded[path] = result
		return result
	end
	world.load = load

	function world.setVariant(on: boolean)
		local name = load("src/shared/Config.luau").Look.StudsVariant
		local existing = materialsMock:FindFirstChild(name)
		if on and not existing then
			local variant = new("MaterialVariant")
			variant.Name = name
			variant.Parent = materialsMock
		elseif not on and existing then
			existing:Destroy()
		end
	end

	function world.setNight(on: boolean)
		workspaceMock:SetAttribute("IsNight", on)
	end

	function world.parts(root)
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A part's bounding corners (lo, hi), in `pivot`'s space when given (a plot's pivot: plot-local studs).
	function world.box(part, pivot)
		local cf = if pivot then pivot:ToObjectSpace(part.CFrame) else part.CFrame
		local s = part.Size / 2
		local lo, hi
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = cf * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		return lo, hi
	end

	return world
end

return World
