--!nocheck
-- T2 of the calm UI build: the HUD BUILT FOR REAL (no Studio here). UI/Kit, UI/Modal and UI/Hud are loaded WHOLE on
-- tests/worldmock Instances with stand-in services (the way tests/Chrome.spec's calm world does it), Hud.init runs,
-- and snapshots are fed to it. It checks what the pure specs can't: that the builders run, which pieces are on
-- screen for a fresh save and a rich one, that new doors arrive one at a time with their line on the Now card, the
-- level row's words, the level-up tap, the "press Send" hint, and the Settings rows.
-- It catches nil calls and wrong structure, not a misspelt property (the mock stores any property).
-- Time is a tiny scheduler: task.spawn / wait / delay run on `clock`, and the spec moves the clock (os.clock too).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local World = require("./worldmock")
local Config = require("./config")
local Schema = require("../src/shared/Logic/Schema")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local LevelsData = require("../src/shared/Data/Levels")
local Belt = require("../src/shared/Logic/Belt")

local function source(path: string): string
	return fs.readFile(World.find(path))
end

local function hudWorld(width: number?, height: number?): any
	local world = World.new()
	local roblox = World.roblox
	local screenSize = roblox.Vector2.new(width or 1280, height or 720)

	-- The scheduler: threads wait on `clock.now`; advance(seconds) runs what is due, in time order.
	local clock = { now = 0 }
	local waiting: { { Thread: thread, At: number, Args: { any } } } = {}
	local function resume(thread: thread, ...: any)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			error("a HUD task failed: " .. tostring(err) .. "\n" .. debug.traceback(thread), 0)
		end
	end
	local task = {}
	function task.spawn(fn, ...)
		resume(coroutine.create(fn), ...)
	end
	function task.defer(fn, ...)
		table.insert(waiting, { Thread = coroutine.create(fn), At = clock.now, Args = { ... } })
	end
	function task.delay(seconds, fn, ...)
		table.insert(waiting, { Thread = coroutine.create(fn), At = clock.now + (seconds or 0), Args = { ... } })
	end
	function task.wait(seconds)
		table.insert(
			waiting,
			{ Thread = coroutine.running(), At = clock.now + math.max(seconds or 0, 0.01), Args = {} }
		)
		return coroutine.yield()
	end
	local function advance(seconds: number)
		local goal = clock.now + seconds
		while true do
			local best = nil
			for index, entry in waiting do
				if entry.At <= goal and (best == nil or entry.At < waiting[best].At) then
					best = index
				end
			end
			if not best then
				break
			end
			local entry = table.remove(waiting, best)
			clock.now = math.max(clock.now, entry.At)
			resume(entry.Thread, table.unpack(entry.Args))
		end
		clock.now = goal
	end

	local function signal(): any
		local listeners = {}
		local self = {}
		function self:Connect(fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					local at = table.find(listeners, fn)
					if at then
						table.remove(listeners, at)
					end
				end,
			}
		end
		function self:Once(fn)
			return self:Connect(fn)
		end
		function self:Fire(...)
			for _, fn in table.clone(listeners) do
				fn(...)
			end
		end
		return self
	end
	local function new(className: string): any
		local instance = world.new(className)
		instance.ZIndex = 1
		instance.Visible = true
		instance.Enabled = true
		instance.Interactable = true
		instance.Text = ""
		instance.AbsoluteSize = roblox.Vector2.new(0, 0)
		instance.AbsolutePosition = roblox.Vector2.new(0, 0)
		rawset(instance, "FindFirstAncestorOfClass", function(self, class) -- the mock has no such method
			local at = self.Parent
			while at and at.ClassName ~= class do
				at = at.Parent
			end
			return at
		end)
		if className == "TextButton" then
			for _, event in { "Activated", "InputBegan", "InputEnded", "MouseEnter", "MouseLeave", "SelectionLost" } do
				instance[event] = signal()
			end
		elseif className == "ScreenGui" then
			-- The mock's IsA doesn't know LayerCollector: say so here, so Kit.isShown works as it does in Roblox.
			instance.AbsoluteSize = screenSize
			local isA = instance.IsA
			rawset(instance, "IsA", function(self, class)
				return class == "LayerCollector" or isA(self, class)
			end)
		end
		return instance
	end

	local player = world.new("Player")
	player:SetAttribute("ReduceEffects", true) -- calm: nothing tweens
	player:SetAttribute("PlotIndex", 1)
	local playerGui = world.new("Folder")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player

	-- Workspace: attributes with real changed signals, and the player's own clinic (Clinics.Plot_1).
	local attributes: { [string]: any } = {}
	local attributeSignals: { [string]: any } = {}
	local clinics = world.new("Folder")
	clinics.Name = "Clinics"
	local plot = world.new("Model")
	plot.Name = "Plot_1"
	plot.Parent = clinics
	local workspace = {
		CurrentCamera = nil,
		GetAttribute = function(_, name)
			return attributes[name]
		end,
		GetAttributeChangedSignal = function(_, name)
			attributeSignals[name] = attributeSignals[name] or signal()
			return attributeSignals[name]
		end,
		FindFirstChild = function(_, name)
			return if name == "Clinics" then clinics else nil
		end,
		WaitForChild = function(_, name)
			return if name == "Clinics" then clinics else nil
		end,
		GetServerTimeNow = function()
			return 1000 + clock.now
		end,
	}
	local function setWorkspace(name: string, value: any)
		attributes[name] = value
		if attributeSignals[name] then
			attributeSignals[name]:Fire()
		end
	end

	local services = {
		Players = { LocalPlayer = player },
		GuiService = { ReducedMotionEnabled = false, SelectedObject = nil },
		UserInputService = { PreferredInput = roblox.Enum.PreferredInput.Touch },
		Workspace = workspace,
		RunService = { RenderStepped = signal(), Heartbeat = signal() },
		TextService = {
			GetTextSize = function(_, text: string, size: number)
				return roblox.Vector2.new(#text * size * 0.5, size)
			end,
		},
		CollectionService = {
			GetTagged = function(_, tag: string)
				return world.tagged(tag)
			end,
		},
		TweenService = {
			Create = function()
				error("nothing tweens in calm mode")
			end,
		},
		ContextActionService = {
			BindActionAtPriority = function() end,
			UnbindAction = function() end,
		},
	}
	local LOGIC = {}
	for _, name in
		{ "Tutorial", "Playtime", "Boosts", "Levels", "LevelBar", "Belt", "Progress", "Tree", "HudZones", "NextEvent" }
	do
		LOGIC[name] = "src/shared/Logic/" .. name .. ".luau"
	end
	local SHARED = {
		Palette = "src/shared/Palette.luau",
		Signal = "src/shared/Signal.luau",
		Types = "src/shared/Types.luau",
		Data = {
			Rarities = "src/shared/Data/Rarities.luau",
			Patients = "src/shared/Data/Patients.luau",
			Regulars = "src/shared/Data/Regulars.luau",
		},
		Logic = LOGIC,
	}
	local function folder(map: any): any
		return {
			WaitForChild = function(_, name: string)
				local found = map[name]
				assert(found, "hudWorld has no Shared." .. name)
				return if type(found) == "table" then folder(found) else found
			end,
		}
	end
	local modules: { [any]: any } = {}
	local shopButton = new("TextButton") -- stands in for Shop.levelUpButton()
	shopButton.Name = "LevelUp"
	local UI: { [string]: any } = {
		Theme = "src/client/UI/Theme.luau",
		Icons = "src/client/UI/Icons.luau",
		Kit = "src/client/UI/Kit.luau",
		Modal = "src/client/UI/Modal.luau",
		Shop = {
			levelUpButton = function()
				return shopButton
			end,
		},
	}
	UI.FindFirstChild = function(_, name)
		return UI[name]
	end
	local WHOLE = { ["/UI/Kit.luau"] = true, ["/UI/Modal.luau"] = true, ["/UI/Hud.luau"] = true }
	local function load(path: any): any
		if type(path) == "table" then
			return path -- a stub (Shop)
		end
		if modules[path] ~= nil then
			return modules[path]
		end
		local whole = false
		for tail in WHOLE do
			whole = whole or string.sub(path, -#tail) == tail
		end
		if not whole then
			modules[path] = world.load(path)
			return modules[path]
		end
		local env: { [string]: any } = {
			game = {
				GetService = function(_, name: string)
					if name == "ReplicatedStorage" then
						return folder({ Shared = SHARED })
					end
					return assert(services[name], "hudWorld has no " .. name)
				end,
			},
			script = { Parent = UI },
			require = load,
			Instance = { new = new },
			TweenInfo = {
				new = function(...)
					return { ... }
				end,
			},
			task = task,
			os = {
				clock = function()
					return clock.now
				end,
				time = os.time,
			},
			warn = function(...)
				error(table.concat({ ... }, " ")) -- a builder that warns is a failure here
			end,
			typeof = function(value: any): string
				if type(value) == "table" and value.ClassName ~= nil then
					return "Instance"
				end
				return typeof(value)
			end,
		}
		for key, value in roblox do
			if env[key] == nil and key ~= "Instance" then
				env[key] = value
			end
		end
		modules[path] = luau.load(source(path), { debugName = path, environment = env })()
		return modules[path]
	end
	local Kit = load(UI.Kit)
	load(UI.Modal)
	local Hud = load("src/client/UI/Hud.luau")
	return {
		Hud = Hud,
		Kit = Kit,
		Icons = load(UI.Icons),
		world = world,
		new = new,
		player = player,
		playerGui = playerGui,
		plot = plot,
		advance = advance,
		setWorkspace = setWorkspace,
		shopButton = shopButton,
	}
end

-- Every Data module, as ctx.Data carries them.
local function allData(world: any): any
	local data = {}
	for _, file in fs.readDir(World.find("src/shared/Data/Levels.luau"):gsub("Levels%.luau$", "")) do
		local name = string.match(file, "^(.+)%.luau$")
		if name then
			data[name] = world.load("src/shared/Data/" .. file)
		end
	end
	return data
end

-- A Snapshot from a save (the same field names), past the tutorial unless `change` says otherwise.
local function snapshot(change: ((any) -> ())?): any
	local data = Schema.default()
	data.Tutorial = TutorialLogic.DONE
	data.TutorialReplay = false
	data.TutorialCures = 0
	data.MailboxReady = false
	data.PlotIndex = 1
	data.TodaysVisitor = ""
	data.VisitorStatus = "None"
	data.IsWinter = false
	data.Simple = false
	data.MakeSeconds = {}
	data.Boosts = { Timed = {}, Permanent = {}, Branch = {}, Rebirth = { Cash = 1, Stars = 1 } }
	if change then
		change(data)
	end
	return data
end

-- A client ctx: the bus, the Snapshot (push sends a new one, as Main.client does), toasts, the remotes Hud touches.
local function hudCtx(W: any, first: any): any
	local handlers: { [string]: { (...any) -> () } } = {}
	local stateHandlers = {}
	local cured = { Fire = nil }
	local curedListeners = {}
	local ctx
	ctx = {
		Data = allData(W.world),
		Config = Config,
		Player = W.player,
		State = first,
		Remotes = {
			Cured = {
				OnClientEvent = {
					Connect = function(_, fn)
						table.insert(curedListeners, fn)
					end,
				},
			},
			Discard = {},
			SetHelpers = {},
			SetSimple = {},
		},
		fired = {},
		toasts = {},
		on = function(name: string, fn: (...any) -> ())
			handlers[name] = handlers[name] or {}
			table.insert(handlers[name], fn)
		end,
		onState = function(fn)
			table.insert(stateHandlers, fn)
		end,
		fire = function(name: string, ...: any)
			table.insert(ctx.fired, { name, ... })
			for _, fn in table.clone(handlers[name] or {}) do
				fn(...)
			end
		end,
		toast = function(text: string)
			table.insert(ctx.toasts, text)
		end,
	}
	function ctx.push(state: any)
		ctx.State = state
		for _, fn in stateHandlers do
			fn(state)
		end
	end
	function ctx.cured()
		for _, fn in curedListeners do
			fn()
		end
	end
	local _ = cured
	return ctx
end

local function screen(W: any, name: string): any
	return W.playerGui:FindFirstChild(name)
end

-- On screen: it and every GuiObject above it are Visible, up to an Enabled ScreenGui.
local function onScreen(W: any, node: any): boolean
	return node ~= nil and W.Kit.isShown(node)
end

local RAIL = { "Shop", "Nurses", "Book", "Badges", "Boards", "Gifts", "Goals", "Mailbox" }

-- The rail doors on screen, in rail order.
local function doors(W: any): { string }
	local out = {}
	for _, name in RAIL do
		if onScreen(W, W.Hud.target(name)) and W.Hud.target(name).Name == name then
			table.insert(out, name)
		end
	end
	return out
end

-- The Now card showing (its text), or nil.
local function nowText(W: any): string?
	local slot = screen(W, "HudNow"):FindFirstChild("Now")
	for _, card in slot:GetChildren() do
		if card:IsA("GuiObject") and card.Visible then
			local text = card:FindFirstChild("Text", true)
			return if text then text.Text else ""
		end
	end
	return nil
end

-- A HUD that has loaded `save` (the default snapshot first, then the server's: the first one never animates).
local function boot(save: any, width: number?, height: number?): (any, any)
	local W = hudWorld(width, height)
	local default = snapshot(function(d)
		d.Tutorial = 0 -- not known yet
		d.PlotIndex = nil
	end)
	local ctx = hudCtx(W, default)
	W.Hud.init(ctx)
	if save then
		ctx.push(save)
	end
	return W, ctx
end

local function level(W: any): any
	return W.Hud.target("Level")
end

T.describe("T2 HUD built for real: what is on screen", function()
	test("before the save arrives: the cash and ⚙️, nothing else", function()
		local W = boot(nil)
		expect(onScreen(W, W.Hud.target("Cash"))).toBe(true)
		expect(onScreen(W, W.Hud.target("Settings"))).toBe(true)
		expect(onScreen(W, W.Hud.target("Stars"))).toBe(false)
		expect(onScreen(W, level(W))).toBe(false)
		expect(doors(W)).toEqual({})
		expect(nowText(W)).toBeNil()
	end)

	test(
		"A FRESH SAVE IS SIMPLE: Lv 1, tutorial just done: the wallet with its level, 2 doors, no Status line",
		function()
			local W = boot(snapshot(function(d)
				d.Cash = 40
				d.Stars = 3
				d.Cured = 3
				d.Book = { DumplingFrog = { Cured = 3, Variants = {} } }
			end))
			expect(onScreen(W, W.Hud.target("Stars"))).toBe(true)
			expect(onScreen(W, level(W))).toBe(true)
			expect(doors(W)).toEqual({ "Shop", "Book" })
			expect(#doors(W) <= 3).toBe(true)
			local status = screen(W, "Hud"):FindFirstChild("Status", true)
			local lines = 0
			for _, row in status:FindFirstChild("Column"):GetChildren() do
				if row:IsA("GuiObject") and row.Visible then
					lines += 1
				end
			end
			expect(lines).toBe(0)
			-- the wallet's numbers
			expect(W.Hud.target("Cash"):FindFirstChild("Amount").Text).toBe("40")
			expect(W.Hud.target("Stars"):FindFirstChild("Amount").Text).toBe("3")
			expect(W.Hud.target("Cash"):FindFirstChild("Icon").Text).toBe(W.Icons.Unit.Cash)
		end
	)

	test("a rich save loses nothing: every door at once when it loads, with no pop and no line", function()
		local W = boot(snapshot(function(d)
			d.Level = 5
			d.Rebirth.Count = 1
			d.Cash = 20000
			d.Stars = 400
			d.Nurses = { DewDuck = { Level = 4, XP = 0, Copies = 2, Job = "" } }
			d.Book = { DumplingFrog = { Cured = 40, Variants = {} } }
			d.Badges = { Healer = 2 }
		end))
		expect(doors(W)).toEqual(RAIL)
		expect(nowText(W) == nil or string.find(nowText(W), "New:", 1, true) == nil).toBe(true)
	end)

	test("a hidden door moves nothing: every rail plate keeps its slot whether its neighbours show or not", function()
		local fresh = boot(snapshot())
		local rich = boot(snapshot(function(d)
			d.Level = 5
		end))
		for _, name in RAIL do
			local a = screen(fresh, "Hud"):FindFirstChild(name, true)
			local b = screen(rich, "Hud"):FindFirstChild(name, true)
			expect(a.Position).toEqual(b.Position)
			expect(a.Size).toEqual(b.Size)
		end
	end)

	test(
		"a phone (640 x 360): it builds, the wallet rides the top-bar row, Badges and Top stay off the rail",
		function()
			local W = boot(
				snapshot(function(d)
					d.Level = 5
					d.Badges = { Healer = 1 }
				end),
				640,
				360
			)
			expect(doors(W)).toEqual({ "Shop", "Nurses", "Book", "Gifts", "Goals", "Mailbox" })
			expect(level(W):FindFirstChild("Badge"):FindFirstChild("Amount").Text).toBe("Lv 5") -- no name on a phone
			expect(level(W):FindFirstChild("Needs").Visible).toBe(false)
		end
	)
end)

T.describe("T2 HUD built for real: doors arrive one at a time", function()
	test(
		"the first nurse can be hired: 👩‍⚕️ pops in with its line on the Now card; the line goes after its hold",
		function()
			local W, ctx = boot(snapshot(function(d)
				d.Cash = 40
			end))
			expect(doors(W)).toEqual({ "Shop" })
			local price = Belt.price(Config, "Common", 1)
			ctx.push(snapshot(function(d)
				d.Cash = price
			end))
			expect(doors(W)).toEqual({ "Shop", "Nurses" })
			expect(nowText(W)).toBe(W.Hud.Pure.DOOR_LINE.Nurses)
			W.advance(W.Hud.Pure.REVEAL_HOLD + 0.1)
			expect(nowText(W) ~= W.Hud.Pure.DOOR_LINE.Nurses).toBe(true)
			-- the cash is spent: the door stays
			ctx.push(snapshot(function(d)
				d.Cash = 0
			end))
			expect(doors(W)).toEqual({ "Shop", "Nurses" })
		end
	)

	test("two doors due together arrive one after the other, never two at once", function()
		local W, ctx = boot(snapshot())
		expect(doors(W)).toEqual({ "Shop" })
		ctx.push(snapshot(function(d)
			d.Cash = 5000
			d.MailboxReady = true
			d.Book = { DumplingFrog = { Cured = 1, Variants = {} } }
		end))
		-- the rail's order: Nurses first (with its line); the Book and the Mail wait their turn
		expect(doors(W)).toEqual({ "Shop", "Nurses" })
		expect(nowText(W)).toBe(W.Hud.Pure.DOOR_LINE.Nurses)
		W.advance(W.Hud.Pure.REVEAL_HOLD + 0.05)
		expect(doors(W)).toEqual({ "Shop", "Nurses", "Book" }) -- the Book has no line: it arrives quietly
		W.advance(W.Hud.Pure.STAGGER + 0.05)
		expect(doors(W)).toEqual({ "Shop", "Nurses", "Book", "Mailbox" })
		expect(nowText(W)).toBe(W.Hud.Pure.DOOR_LINE.Mailbox)
		W.advance(W.Hud.Pure.REVEAL_HOLD + 1)
		expect(nowText(W) ~= W.Hud.Pure.DOOR_LINE.Mailbox).toBe(true)
	end)

	test("the first night: the day and night line and the goals arrive", function()
		local W = boot(snapshot())
		W.setWorkspace("PhaseEndsAt", 1300)
		local clock = screen(W, "Hud"):FindFirstChild("Clock", true)
		W.advance(1)
		expect(clock.Visible).toBe(false)
		expect(table.find(doors(W), "Goals")).toBeNil()
		W.setWorkspace("IsNight", true)
		W.advance(30)
		expect(table.find(doors(W), "Goals") ~= nil).toBe(true)
		expect(clock.Visible).toBe(true)
	end)

	test("the tutorial's own steps: ⭐ with the first treatment, 🛒 at the shop step", function()
		local W, ctx = boot(snapshot(function(d)
			d.Tutorial = TutorialLogic.REST
		end))
		expect(onScreen(W, W.Hud.target("Stars"))).toBe(false)
		ctx.cured()
		W.advance(1)
		expect(onScreen(W, W.Hud.target("Stars"))).toBe(true)
		expect(doors(W)).toEqual({})
		ctx.push(snapshot(function(d)
			d.Tutorial = TutorialLogic.SHOP
		end))
		W.advance(1)
		expect(doors(W)).toEqual({ "Shop" })
		expect(onScreen(W, level(W))).toBe(false) -- the level row waits for the tutorial's end
	end)
end)

T.describe("T2 HUD built for real: the level row", function()
	local next2 = LevelsData[2]

	test("'Lv 1 Clinic', the bar, and what the next level needs as two Units", function()
		local W = boot(snapshot(function(d)
			d.Cash = 300
			d.Stars = 12
		end))
		local row = level(W)
		expect(row:FindFirstChild("Badge"):FindFirstChild("Icon").Text).toBe(W.Icons.Unit.Level)
		expect(row:FindFirstChild("Badge"):FindFirstChild("Amount").Text).toBe("Lv 1 " .. LevelsData[1].Name)
		expect(row:FindFirstChild("Bar"):GetAttribute("Fraction")).toBeCloseTo(
			(12 / next2.Stars + 300 / next2.Cash) / 2
		)
		local needs = row:FindFirstChild("Needs")
		expect(needs.Visible).toBe(true)
		expect(needs:FindFirstChild("Stars"):FindFirstChild("Icon").Text).toBe(W.Icons.Unit.Stars)
		expect(needs:FindFirstChild("Stars"):FindFirstChild("Amount").Text).toBe("12/" .. next2.Stars)
		expect(needs:FindFirstChild("Cash"):FindFirstChild("Amount").Text).toBe("300/" .. next2.Cash)
		expect(row:FindFirstChild("Ready").Visible).toBe(false)
	end)

	test("not ready: a tap says what the next level is and needs; nothing opens", function()
		local W, ctx = boot(snapshot(function(d)
			d.Cash = 300
			d.Stars = 12
		end))
		level(W).Activated:Fire()
		expect(#ctx.toasts).toBe(1)
		expect(string.find(ctx.toasts[1], "Lv 2 " .. next2.Name, 1, true) ~= nil).toBe(true)
		expect(#ctx.fired).toBe(0)
	end)

	test("ready: 'Level up!', the Now card points at it, and a tap opens the Shop on its Hospital tab", function()
		local W, ctx = boot(snapshot(function(d)
			d.Cash = 40
			d.Stars = next2.Stars
			d.Nurses = { DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" } }
		end))
		expect(nowText(W) ~= W.Hud.Pure.TEXT.LevelUp).toBe(true)
		ctx.push(snapshot(function(d)
			d.Cash = next2.Cash
			d.Stars = next2.Stars
			d.Nurses = { DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" } }
		end))
		local row = level(W)
		expect(row:FindFirstChild("Ready").Visible).toBe(true)
		expect(row:FindFirstChild("Ready").Text).toBe("Level up!")
		expect(row:FindFirstChild("Needs").Visible).toBe(false)
		expect(row:FindFirstChild("Bar"):GetAttribute("Fraction")).toBe(1)
		expect(nowText(W)).toBe(W.Hud.Pure.TEXT.LevelUp)
		row.Activated:Fire()
		expect(ctx.fired[#ctx.fired]).toEqual({ "Open", "Shop", "Hospital" })
		W.advance(1) -- the Shop's Level up button is looked up after it opens (the stub's isn't on screen: no error)
		expect(nowText(W) ~= W.Hud.Pure.TEXT.LevelUp).toBe(true) -- once a session
		ctx.push(snapshot(function(d)
			d.Cash = next2.Cash + 5
			d.Stars = next2.Stars
			d.Nurses = { DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" } }
		end))
		expect(nowText(W) ~= W.Hud.Pure.TEXT.LevelUp).toBe(true)
	end)

	test("a tap on the Now card's level-up line opens the Shop's Hospital tab too", function()
		local W, ctx = boot(snapshot(function(d)
			d.Cash = next2.Cash
			d.Stars = next2.Stars
		end))
		W.advance(60) -- any new doors have had their turn
		expect(nowText(W)).toBe(W.Hud.Pure.TEXT.LevelUp)
		local plate = screen(W, "HudNow"):FindFirstChild("Hint", true):FindFirstChild("Plate")
		plate.Activated:Fire()
		expect(ctx.fired[#ctx.fired]).toEqual({ "Open", "Shop", "Hospital" })
	end)

	test("every Star passed but the level not bought: it never says everything is unlocked, and never Max", function()
		local W = boot(snapshot(function(d)
			d.Level = 2
			d.Stars = 9999
			d.Cash = 0
		end))
		local row = level(W)
		expect(row:FindFirstChild("Ready").Visible).toBe(false)
		expect(row:FindFirstChild("Needs").Visible).toBe(true)
		for _, node in W.playerGui:GetDescendants() do
			if type(node.Text) == "string" then
				expect(string.find(node.Text, "unlocked", 1, true)).toBeNil()
				expect(string.find(node.Text, "Max", 1, true)).toBeNil()
			end
		end
	end)

	test("the top level: a calm 'Max level', a full bar, no needs; a tap says so and opens nothing", function()
		local W, ctx = boot(snapshot(function(d)
			d.Level = #LevelsData
		end))
		local row = level(W)
		expect(row:FindFirstChild("Ready").Text).toBe("Max level")
		expect(row:FindFirstChild("Ready").Visible).toBe(true)
		expect(row:FindFirstChild("Needs").Visible).toBe(false)
		expect(row:FindFirstChild("Bar"):GetAttribute("Fraction")).toBe(1)
		row.Activated:Fire()
		expect(ctx.toasts[1]).toBe("Max level")
		expect(#ctx.fired).toBe(0)
	end)
end)

T.describe("T2 HUD built for real: 'Patients wait for you: press Send'", function()
	local function waitingPatient(W: any, parent: any): any
		local prompt = W.world.new("ProximityPrompt")
		prompt.Name = W.Hud.Pure.SEND_PROMPT.Name
		prompt.Enabled = true
		prompt:AddTag(W.Hud.Pure.SEND_PROMPT.Tag)
		prompt.Parent = parent
		return prompt
	end

	test("a patient waits a while in YOUR clinic: the hint shows once, and goes when it is sent", function()
		local W = boot(snapshot())
		local prompt = waitingPatient(W, W.plot)
		W.advance(W.Hud.Pure.SEND_HINT.After - 4)
		expect(nowText(W) ~= W.Hud.Pure.TEXT.Send).toBe(true)
		W.advance(8)
		expect(nowText(W)).toBe(W.Hud.Pure.TEXT.Send)
		prompt.Enabled = false -- sent
		W.advance(3)
		expect(nowText(W) ~= W.Hud.Pure.TEXT.Send).toBe(true)
		-- once a session: another long wait says nothing
		waitingPatient(W, W.plot)
		W.advance(60)
		expect(nowText(W) ~= W.Hud.Pure.TEXT.Send).toBe(true)
	end)

	test("it holds a few seconds at most, and a patient in someone else's clinic never shows it", function()
		local W = boot(snapshot())
		waitingPatient(W, W.plot)
		W.advance(W.Hud.Pure.SEND_HINT.After + 3)
		expect(nowText(W)).toBe(W.Hud.Pure.TEXT.Send)
		W.advance(W.Hud.Pure.SEND_HINT.Hold + 3)
		expect(nowText(W) ~= W.Hud.Pure.TEXT.Send).toBe(true)

		local other = boot(snapshot())
		local elsewhere = other.world.new("Model")
		waitingPatient(other, elsewhere)
		other.advance(60)
		expect(nowText(other) ~= other.Hud.Pure.TEXT.Send).toBe(true)
	end)

	test("never during the tutorial (its own card leads)", function()
		local W = boot(snapshot(function(d)
			d.Tutorial = TutorialLogic.PATIENT
		end))
		waitingPatient(W, W.plot)
		W.advance(60)
		expect(nowText(W)).toBeNil()
	end)
end)

T.describe("T2 HUD built for real: ⚙️ Settings", function()
	local function rows(W: any): { any }
		local list = screen(W, "Settings") or W.playerGui:FindFirstChild("Rows", true).Parent
		local out = {}
		for _, node in W.playerGui:FindFirstChild("Rows", true):GetChildren() do
			if node.ClassName == "TextButton" and node.Visible then
				table.insert(out, node)
			end
		end
		table.sort(out, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local _ = list
		return out
	end

	test("a fresh player: three switches with fixed labels, the owner's switch, Replay as a Quiet link", function()
		local W = boot(snapshot())
		W.Hud.target("Settings").Activated:Fire()
		local names, kinds = {}, {}
		for _, row in rows(W) do
			table.insert(names, row.Name)
			table.insert(kinds, if row:FindFirstChild("Switch") then "Toggle" else row:GetAttribute("KitKind"))
		end
		expect(names).toEqual({ "Music", "Effects", "Simple", "Helpers", "Replay" })
		expect(kinds).toEqual({ "Toggle", "Toggle", "Toggle", "Toggle", "Quiet" })
		local labels = {}
		for _, row in rows(W) do
			local label = row:FindFirstChild("Label")
			table.insert(labels, if label then label.Text else row.Text)
		end
		expect(labels).toEqual({ "Music", "Effects", "Mini-games", "Anyone can help", "Replay tutorial" })
		for _, text in labels do
			expect(W.Icons.count(text)).toBe(0)
		end
	end)

	test("a switch shows the state and its label never changes: Music off, Effects calm, Simple taps", function()
		local W, ctx = boot(snapshot())
		W.Hud.target("Settings").Activated:Fire()
		local function row(name: string): any
			return W.playerGui:FindFirstChild("Rows", true):FindFirstChild(name)
		end
		expect(row("Music"):GetAttribute("On")).toBe(true)
		expect(row("Effects"):GetAttribute("On")).toBe(false) -- this test world is calm (ReduceEffects)
		expect(row("Simple"):GetAttribute("On")).toBe(true) -- mini-games on
		row("Music").Activated:Fire()
		expect(W.player:GetAttribute("MusicMuted")).toBe(true)
		expect(row("Music"):GetAttribute("On")).toBe(false)
		expect(row("Music"):FindFirstChild("Label").Text).toBe("Music")
		ctx.push(snapshot(function(d)
			d.Simple = true
		end))
		expect(row("Simple"):GetAttribute("On")).toBe(false)
		expect(row("Simple"):FindFirstChild("Label").Text).toBe("Mini-games")
	end)

	test("the title is words only, and Badges and Top are links on a phone once the first badge is earned", function()
		local W = boot(
			snapshot(function(d)
				d.Badges = { Healer = 1 }
			end),
			640,
			360
		)
		W.Hud.target("Settings").Activated:Fire()
		local names = {}
		for _, row in rows(W) do
			table.insert(names, row.Name)
		end
		expect(table.find(names, "Badges") ~= nil).toBe(true)
		expect(table.find(names, "Boards") ~= nil).toBe(true)
		local link = W.playerGui:FindFirstChild("Rows", true):FindFirstChild("Boards")
		expect(link.Text).toBe("Top")
		expect(link:GetAttribute("KitKind")).toBe("Quiet")
		local fresh = boot(snapshot(), 640, 360)
		fresh.Hud.target("Settings").Activated:Fire()
		for _, row in rows(fresh) do
			expect(row.Name ~= "Badges" and row.Name ~= "Boards").toBe(true)
		end
	end)
end)
