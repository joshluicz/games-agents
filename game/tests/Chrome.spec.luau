--!strict
-- The chrome (look build plan T6, §B8): the one modal template, the button roles, the one tab and the one text fit,
-- checked on the shipped code. Kit.Juice and Modal.Pure are loaded from their marked blocks; Kit.textLimit runs on
-- its own with a stand-in Instance; the rest reads the source of every T6 file (uirules and the template's rules).
-- The calm UI (docs/plan/2026-11-17-ui-direction.md T0; Joshua, memory-20261117-007): the outline budget on the
-- looks, the new pure helpers, and THE CALM PARTS BUILT FOR REAL: Kit and Modal are loaded whole with tests/worldmock
-- Instances and stand-in services (calm mode, so nothing tweens), and every new part is made and looked at.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local UiRules = require("./uirules")
local World = require("./worldmock")
local expect, test = T.expect, T.test

local root = if fs.isFile("src/client/UI/Kit.luau") then "." else "game"
local function source(path: string): string
	return fs.readFile(root .. "/" .. path)
end

local function block(path: string, startMark: string, endMark: string, name: string): any
	local text = source(path)
	local first = string.find(text, startMark, 1, true)
	local last = string.find(text, endMark, 1, true)
	assert(first and last, "markers missing in " .. path)
	return luau.load(string.sub(text, first, last - 1) .. "\nreturn " .. name, { debugName = path })()
end

local Juice = block("src/client/UI/Kit.luau", "-- BEGIN JUICE", "-- END JUICE", "Juice")
local ModalPure = block("src/client/UI/Modal.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
local MiniPure = (function()
	local text = source("src/client/UI/MiniGames.luau")
	local first = string.find(text, "PURE:BEGIN", 1, true) :: number
	local from = (string.find(text, "\n", first, true) :: number) + 1
	local upto = (string.find(text, "\n[^\n]*PURE:END", from) :: number) - 1
	return luau.load(string.sub(text, from, upto) .. "\nreturn Pure", { debugName = "MiniGames.Pure" })()
end)()

local T6_FILES = {
	"src/client/UI/Modal.luau",
	"src/client/UI/Kit.luau",
	"src/client/UI/Shop.luau",
	"src/client/UI/BookPanel.luau",
	"src/client/UI/Boards.luau",
	"src/client/UI/BadgeBook.luau",
	"src/client/UI/Mailbox.luau",
	"src/client/UI/PlayGifts.luau",
	"src/client/UI/DayReportPanel.luau",
	"src/client/UI/AdminPanel.luau",
	"src/client/UI/MiniGames.luau",
}
local PANELS = {
	"Shop",
	"BookPanel",
	"Boards",
	"BadgeBook",
	"Mailbox",
	"PlayGifts",
	"DayReportPanel",
	"AdminPanel",
	"MiniGames",
}

-- The code of a file without its comments (so a rule never trips on its own explanation).
local function code(path: string): string
	local out = {}
	for line in string.gmatch(source(path) .. "\n", "(.-)\r?\n") do
		local body = string.gsub(line, "%s*%-%-.*$", "")
		table.insert(out, body)
	end
	return table.concat(out, "\n")
end

local function count(text: string, needle: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(text, needle, from, true)
		if not at then
			return n
		end
		n += 1
		from = at + #needle
	end
end

T.describe("Kit roles (§B8, ux audit §3.3)", function()
	test("the six roles are themselves; nil is Primary (Kit.button's old default)", function()
		expect(Juice.ROLES).toEqual({ "Primary", "Collect", "Secondary", "Quiet", "Destructive", "Icon" })
		for _, role in Juice.ROLES do
			expect(Juice.role(role)).toBe(role)
		end
		expect(Juice.role(nil)).toBe("Primary")
	end)
	test("the old colour kinds map onto the roles", function()
		expect(Juice.role("Good")).toBe("Collect")
		expect(Juice.role("Danger")).toBe("Destructive")
		for _, kind in { "Pink", "Purple", "Cyan", "Cash" } do
			expect(Juice.role(kind)).toBe("Secondary")
		end
		expect(Juice.role("Card")).toBe("Quiet")
	end)
	test("Disabled is a look; anything unknown is the calm Secondary, never a loud colour", function()
		expect(Juice.role("Disabled")).toBe("Disabled")
		expect(Juice.role("Rainbow")).toBe("Secondary")
		expect(Juice.role(42)).toBe("Secondary")
		expect(Juice.role({})).toBe("Secondary")
	end)
	test("the looks: candy for Primary, Collect and Destructive; ink and flat for the rest", function()
		for _, role in { "Primary", "Collect", "Destructive" } do
			local look = Juice.LOOKS[role]
			expect(look.Candy).toBe(true)
			expect(look.Text).toBe("OnColor")
			expect(look.Stroke).toBe("Bold")
			expect(look.Fill).toBe(role)
		end
		expect(Juice.LOOKS.Secondary.Candy).toBe(false)
		expect(Juice.LOOKS.Secondary.Text).toBe("Ink")
		expect(Juice.LOOKS.Secondary.Stroke).toBeNil() -- the calm UI: a flat fill, no line
		expect(Juice.LOOKS.Quiet.Clear).toBe(true) -- no fill ...
		expect(Juice.LOOKS.Quiet.Stroke).toBeNil() -- ... and no outline: a link
		expect(Juice.LOOKS.Icon.Fill).toBe("Plate") -- the white plate ...
		expect(Juice.LOOKS.Icon.Stroke).toBe("Bold") -- ... with the Bold outline
		expect(Juice.LOOKS.Disabled.Fill).toBe("Disabled")
		expect(Juice.LOOKS.Disabled.Text).toBe("DisabledText")
		expect(Juice.look("Good")).toBe(Juice.LOOKS.Collect)
	end)
	test("the outline budget (R2): only Primary, Collect, Destructive and Icon carry a stroke", function()
		local stroked = {}
		for name, look in Juice.LOOKS do
			if look.Stroke ~= nil then
				table.insert(stroked, name)
			end
		end
		table.sort(stroked)
		expect(stroked).toEqual({ "Collect", "Destructive", "Icon", "Primary" })
		expect(Juice.LOOKS.Disabled.Stroke).toBeNil()
	end)
	test("every look's colour and stroke is a Theme token", function()
		local theme = source("src/client/UI/Theme.luau")
		for name, look in Juice.LOOKS do
			for _, key in { look.Fill, look.Text } do
				assert(
					string.find(theme, "\n\t" .. key .. " = ", 1, true),
					name .. ": Theme.Colors." .. key .. " missing"
				)
			end
			if look.Stroke then
				assert(string.find(theme, "\n\t" .. look.Stroke .. " = ", 1, true), name .. ": Theme.Stroke missing")
			end
		end
	end)
	test("only a Collect button may shine or breathe (red line 3: nothing loud points at spending)", function()
		expect(Juice.mayLoop("Collect")).toBe(true)
		for _, role in { "Primary", "Secondary", "Quiet", "Destructive", "Icon", "Disabled", nil } do
			expect(Juice.mayLoop(role)).toBe(false)
		end
	end)
end)

T.describe("The motion budget (Theme.Motion.Perpetual = 1)", function()
	test("one owner at a time: the topmost screen wins, then the oldest", function()
		expect(Juice.pickPerpetual({})).toBeNil()
		expect(Juice.pickPerpetual({ { Order = 20, Seq = 5 } })).toBe(1)
		-- A popup's Collect (DisplayOrder 30) over a panel's (20).
		expect(Juice.pickPerpetual({ { Order = 20, Seq = 1 }, { Order = 30, Seq = 9 } })).toBe(2)
		-- Two goals' claim buttons on one panel: the first made.
		expect(Juice.pickPerpetual({ { Order = 20, Seq = 7 }, { Order = 20, Seq = 3 }, { Order = 20, Seq = 4 } })).toBe(
			2
		)
	end)
	test("Kit's loop asks it, and the red dot no longer hops (it pops once)", function()
		local kit = code("src/client/UI/Kit.luau")
		assert(string.find(kit, "Juice.pickPerpetual(candidates)", 1, true), "the loop picks one owner")
		assert(string.find(kit, 'Juice.mayLoop(owner:GetAttribute("KitKind"))', 1, true), "only Collect owners")
		expect(count(kit, "startDotHops")).toBe(0)
		expect(count(kit, "DotHopEvery")).toBe(0)
	end)
end)

T.describe("Kit.textLimit: THE text fit, never under 18", function()
	-- Kit.textLimit on its own, with a stand-in Instance and Theme.
	local text = source("src/client/UI/Kit.luau")
	local first = string.find(text, "function Kit.textLimit", 1, true) :: number
	local last = (string.find(text, "\nend\n", first, true) :: number) + 4
	local made = 0
	local env = {
		Kit = {},
		Theme = { TextSize = { Caption = 18 } },
		math = math,
		Instance = {
			new = function(className: string): any
				made += 1
				return { ClassName = className }
			end,
		},
	}
	luau.load(string.sub(text, first, last), { debugName = "Kit.textLimit", environment = env })()
	local function label(): any
		local children = {}
		local fake = {}
		function fake.FindFirstChildOfClass(_: any, className: string): any
			for _, child in children do
				if child.ClassName == className then
					return child
				end
			end
			return nil
		end
		setmetatable(fake, {
			__newindex = function(_, key, value)
				rawset(fake, key, value)
			end,
		})
		fake.children = children
		return fake
	end
	test("MinTextSize is the 18 px floor; MaxTextSize never under it", function()
		local a = label()
		local limit = env.Kit.textLimit(a, 30)
		expect(limit.MinTextSize).toBe(18)
		expect(limit.MaxTextSize).toBe(30)
		local b = label()
		local small = env.Kit.textLimit(b, 12)
		expect(small.MinTextSize).toBe(18)
		expect(small.MaxTextSize).toBe(18)
		expect(small.Parent).toBe(b)
	end)
	test("an existing constraint is reused, not stacked", function()
		local a = label()
		local existing = { ClassName = "UITextSizeConstraint", MinTextSize = 9, MaxTextSize = 9 }
		table.insert(a.children, existing)
		local before = made
		local limit = env.Kit.textLimit(a, 24)
		expect(limit).toBe(existing)
		expect(made).toBe(before)
		expect(existing.MinTextSize).toBe(18)
		expect(existing.MaxTextSize).toBe(24)
	end)
end)

T.describe("Modal: the template's rules (Modal.Pure)", function()
	test("HudMode: Panel for panels, None for popups, Game when asked", function()
		expect(ModalPure.hudMode(nil, nil)).toBe("Panel")
		expect(ModalPure.hudMode("Panel", nil)).toBe("Panel")
		expect(ModalPure.hudMode("Popup", nil)).toBe("None")
		expect(ModalPure.hudMode("Panel", "Game")).toBe("Game")
		expect(ModalPure.hudMode("Popup", "Panel")).toBe("Panel")
		expect(ModalPure.hudMode("Panel", "Loud")).toBe("Panel")
	end)
	test("closable: a ✖ or a dim that closes; the mini-game (neither) never closes on ButtonB", function()
		expect(ModalPure.closable({})).toBe(true)
		expect(ModalPure.closable({ CloseButton = false })).toBe(true) -- the dim still closes it
		expect(ModalPure.closable({ CloseButton = false, DimCloses = false })).toBe(false)
		expect(ModalPure.closable({ CloseButton = false, Dim = false })).toBe(false)
		expect(ModalPure.closable({ Dim = false })).toBe(true) -- the Day Report's ✖
		expect(ModalPure.closable(nil)).toBe(true)
	end)
	test("the confirm: 'Not now' is always there and always the default focus", function()
		local c = ModalPure.confirm({
			Title = "Skip the tutorial?",
			Line = "You can replay it any time from Settings",
			Yes = "Skip",
		})
		expect(c.No).toBe("Not now")
		expect(c.Focus).toBe("No")
		expect(c.Kind).toBe("Primary")
		expect(c.Hold).toBe(0)
		expect(c.Line).toBe("You can replay it any time from Settings")
		expect(ModalPure.confirm({ Title = "x", Line = "y", Yes = "z", No = "Keep going" }).No).toBe("Keep going")
		expect(ModalPure.confirm({ Title = "x", Line = "y", Yes = "z", No = "" }).No).toBe("Not now")
	end)
	test("the confirm: its role is Primary, Destructive or Collect; a hold is never negative", function()
		expect(ModalPure.confirm({ Kind = "Destructive" }).Kind).toBe("Destructive")
		expect(ModalPure.confirm({ Kind = "Collect" }).Kind).toBe("Collect")
		expect(ModalPure.confirm({ Kind = "Pink" }).Kind).toBe("Primary")
		expect(ModalPure.confirm({ Hold = 1 }).Hold).toBe(1)
		expect(ModalPure.confirm({ Hold = 1.5 }).Hold).toBe(1.5)
		expect(ModalPure.confirm({ Hold = -3 }).Hold).toBe(0)
		expect(ModalPure.confirm({ Hold = 0 / 0 }).Hold).toBe(0)
		local junk = ModalPure.confirm(nil)
		expect(junk.Title).toBe("Sure?")
		expect(junk.No).toBe("Not now")
		expect(junk.Focus).toBe("No")
	end)
	test("the confirm is the 420 x 360 popup; the odds popup the same width", function()
		expect(ModalPure.CONFIRM_SIZE).toEqual({ X = 420, Y = 360 })
		expect(ModalPure.ODDS_SIZE.X).toBe(420)
	end)
	test("the odds rows: the word AND the true number, never rounded to a friendlier one", function()
		expect(ModalPure.oddsLine({ Icon = "💙", Name = "Rare", Percent = 20 })).toBe("Rare 20%")
		expect(ModalPure.percent(4.5)).toBe("4.5%")
		expect(ModalPure.percent(0.5)).toBe("0.5%")
		expect(ModalPure.percent(0.05)).toBe("0.05%")
		expect(ModalPure.percent(12.25)).toBe("12.25%")
		expect(ModalPure.percent(100)).toBe("100%")
		expect(ModalPure.percent(0 / 0)).toBe("0%")
		expect(ModalPure.percent("lots")).toBe("0%")
		expect(ModalPure.oddsLine(nil)).toBe("? 0%")
	end)
	test("the ✖ is 48 px: inside the 64 px band with 8 px around it", function()
		expect(ModalPure.CLOSE).toBe(48)
		local kit = source("src/client/UI/Kit.luau")
		local band = tonumber(string.match(kit, "\nKit%.HEADER = (%d+)")) :: number
		expect((band - ModalPure.CLOSE) / 2).toBe(8)
		assert(ModalPure.CLOSE >= 44, "still a comfortable tap")
	end)
	test("only the tabs with something in them (R0): hidden ones drop out, in the tabs' own order", function()
		local tabs = { { Id = "Team" }, { Id = "Common" }, { Id = "Rare" } }
		expect(ModalPure.shownTabs(tabs, {})).toEqual({ "Team", "Common", "Rare" })
		expect(ModalPure.shownTabs(tabs, { Common = true })).toEqual({ "Team", "Rare" })
		expect(ModalPure.shownTabs(tabs, { Common = true, Rare = true, Team = false })).toEqual({ "Team" })
		expect(ModalPure.shownTabs(tabs, nil)).toEqual({ "Team", "Common", "Rare" })
		expect(ModalPure.shownTabs(nil, nil)).toEqual({})
		expect(ModalPure.shownTabs({ 7, { Id = 3 }, { Id = "Ok" } }, {})).toEqual({ "Ok" })
	end)
	test("no tab column for one kind of thing: it needs two tabs or more", function()
		expect(ModalPure.tabColumn(0)).toBe(false)
		expect(ModalPure.tabColumn(1)).toBe(false)
		expect(ModalPure.tabColumn(2)).toBe(true)
		expect(ModalPure.tabColumn(7)).toBe(true)
		expect(ModalPure.tabColumn(nil)).toBe(false)
	end)
	test("a tab fits a one-word caption at the 18 px floor (about 10 px a letter)", function()
		for _, caption in { "Upgrades", "Hospital", "Patients", "Stations", "Branches" } do
			assert(#caption * 10 <= ModalPure.TAB_WIDTH, caption .. " is wider than a tab")
		end
		assert(ModalPure.TAB_WIDTH >= 56, "a tab is at least the 56 px tap minimum")
	end)
end)

T.describe("The calm UI: Kit.Juice's new helpers", function()
	test("barFraction: a share of a goal, clamped; junk and a zero goal are empty", function()
		expect(Juice.barFraction(5, 20)).toBe(0.25)
		expect(Juice.barFraction(20, 20)).toBe(1)
		expect(Juice.barFraction(50, 20)).toBe(1)
		expect(Juice.barFraction(-3, 20)).toBe(0)
		expect(Juice.barFraction(5, 0)).toBe(0)
		expect(Juice.barFraction(5, -1)).toBe(0)
		expect(Juice.barFraction("x", 20)).toBe(0)
		expect(Juice.barFraction(0 / 0, 20)).toBe(0)
		expect(Juice.barFraction(0.4, nil)).toBe(0.4) -- already a fraction
		expect(Juice.barFraction(1.7, nil)).toBe(1)
	end)
	test("nextReveal: HUD doors arrive one at a time, in the rail's order, only when they have content", function()
		local order = { "Shop", "Nurses", "Book", "Goals", "Mail", "Gifts" }
		expect(Juice.nextReveal(order, {}, {})).toBeNil()
		expect(Juice.nextReveal(order, { Mail = true, Nurses = true }, {})).toBe("Nurses")
		expect(Juice.nextReveal(order, { Mail = true, Nurses = true }, { Nurses = true })).toBe("Mail")
		expect(Juice.nextReveal(order, { Mail = true, Nurses = true }, { Nurses = true, Mail = true })).toBeNil()
		expect(Juice.nextReveal(order, { Topiary = true }, {})).toBeNil() -- not a door on the rail
		-- Walking the queue shows every wanted door exactly once, never two together.
		local wanted = { Shop = true, Book = true, Gifts = true }
		local shown, steps = {}, {}
		while true do
			local id = Juice.nextReveal(order, wanted, shown)
			if not id then
				break
			end
			shown[id] = true
			table.insert(steps, id)
		end
		expect(steps).toEqual({ "Shop", "Book", "Gifts" })
	end)
	test("menuPlace: under its anchor, right edges in line; above when there is no room; always on screen", function()
		local screen = { W = 568, H = 320 }
		local menu = { W = 200, H = 132 }
		local x, y = Juice.menuPlace({ X = 300, Y = 60, W = 88, H = 56 }, menu, screen, 4)
		expect(x).toBe(188) -- 300 + 88 - 200
		expect(y).toBe(120) -- 60 + 56 + 4
		-- Low on the phone floor: it flips above.
		local _, above = Juice.menuPlace({ X = 300, Y = 240, W = 88, H = 56 }, menu, screen, 4)
		expect(above).toBe(104) -- 240 - 4 - 132
		-- Hard against the left edge: pushed back inside.
		local left = Juice.menuPlace({ X = 10, Y = 60, W = 88, H = 56 }, menu, screen, 4)
		expect(left).toBe(4)
		-- Every anchor on the phone floor keeps the whole menu on screen.
		for ax = 0, 480, 40 do
			for ay = 0, 264, 24 do
				local mx, my = Juice.menuPlace({ X = ax, Y = ay, W = 88, H = 56 }, menu, screen, 4)
				assert(mx >= 4 and mx + menu.W <= screen.W - 4, "x off screen at " .. ax .. "," .. ay)
				assert(my >= 4 and my + menu.H <= screen.H - 4, "y off screen at " .. ax .. "," .. ay)
			end
		end
	end)
end)

-- Kit and Modal loaded WHOLE: tests/worldmock Instances (plain tables that store any property), Lune's own roblox
-- datatypes, and stand-in services. The player has ReduceEffects on, so Kit.reducedMotion() is true and nothing
-- tweens. Buttons get real Activated signals, so a test can press them.
local function calmWorld(): any
	local world = World.new()
	local roblox = World.roblox
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
		instance.AbsoluteSize = roblox.Vector2.new(0, 0)
		instance.AbsolutePosition = roblox.Vector2.new(0, 0)
		if className == "TextButton" then
			for _, event in { "Activated", "InputBegan", "InputEnded", "MouseEnter", "MouseLeave", "SelectionLost" } do
				instance[event] = signal()
			end
		end
		return instance
	end
	local player = world.new("Player")
	player:SetAttribute("ReduceEffects", true)
	local playerGui = world.new("Folder")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	local bound: { [string]: boolean } = {}
	local guiService = { ReducedMotionEnabled = false, SelectedObject = nil }
	local services = {
		Players = { LocalPlayer = player },
		GuiService = guiService,
		UserInputService = { PreferredInput = roblox.Enum.PreferredInput.Touch },
		TweenService = {
			Create = function()
				error("nothing tweens in calm mode")
			end,
		},
		ContextActionService = {
			BindActionAtPriority = function(_, name: string)
				bound[name] = true
			end,
			UnbindAction = function(_, name: string)
				bound[name] = nil
			end,
		},
	}
	local SHARED = {
		Palette = "src/shared/Palette.luau",
		Signal = "src/shared/Signal.luau",
		Types = "src/shared/Types.luau",
		Data = { Rarities = "src/shared/Data/Rarities.luau" },
	}
	local function folder(map: any): any
		return {
			WaitForChild = function(_, name: string)
				local found = map[name]
				assert(found, "calmWorld has no Shared." .. name)
				return if type(found) == "table" then folder(found) else found
			end,
		}
	end
	local modules: { [string]: any } = {}
	local load: (path: string) -> any
	local UI = {
		Theme = "src/client/UI/Theme.luau",
		Icons = "src/client/UI/Icons.luau",
		Kit = "src/client/UI/Kit.luau",
	}
	function load(path: string): any
		if modules[path] ~= nil then
			return modules[path]
		end
		if not string.find(path, "/UI/Kit.luau", 1, true) and not string.find(path, "/UI/Modal.luau", 1, true) then
			modules[path] = world.load(path)
			return modules[path]
		end
		local env: { [string]: any } = {
			game = {
				GetService = function(_, name: string)
					if name == "ReplicatedStorage" then
						return folder({ Shared = SHARED })
					end
					return assert(services[name], "calmWorld has no " .. name)
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
			task = require("@lune/task"),
			warn = function() end,
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
	return {
		Kit = load("src/client/UI/Kit.luau"),
		Modal = load("src/client/UI/Modal.luau"),
		Theme = load("src/client/UI/Theme.luau"),
		Icons = load("src/client/UI/Icons.luau"),
		new = new,
		playerGui = playerGui,
		bound = bound,
		gui = guiService,
		roblox = roblox,
		ctx = { fire = function() end },
	}
end

-- Every UIStroke that draws a shape outline under `root` (root included), not a text outline.
local function borders(root: any): { any }
	local out = {}
	local all = root:GetDescendants()
	for _, node in all do
		if
			node.ClassName == "UIStroke"
			and node.Name ~= "TextOutline"
			and node.Enabled ~= false
			and node.ApplyStrokeMode ~= World.roblox.Enum.ApplyStrokeMode.Contextual
		then
			table.insert(out, node)
		end
	end
	return out
end

T.describe("The calm parts, built for real (Kit loaded whole)", function()
	local W = calmWorld()
	local Kit, Theme, Icons = W.Kit, W.Theme, W.Icons

	test("every old Kit key is still there, and the new ones too (T1 to T5 land in any order)", function()
		for _, name in
			{
				"screen",
				"panel",
				"label",
				"button",
				"setRole",
				"tab",
				"textLimit",
				"iconButton",
				"setDot",
				"setEnabled",
				"corner",
				"pad",
				"stroke",
				"outline",
				"list",
				"popIn",
				"popOut",
				"shade",
				"lighten",
				"shine",
				"rays",
				"bump",
				"punch",
				"gloss",
				"isShown",
				"countUp",
				"celebrate",
				"confetti",
				"rarityFrame",
				"rarityColor",
				"breathing",
				"ring",
				"holdButton",
				"reducedMotion",
				-- the calm UI
				"card",
				"name",
				"fact",
				"voice",
				"bar",
				"artTile",
				"setState",
				"unit",
				"toggle",
				"more",
				"menu",
				"reveal",
			}
		do
			assert(type(Kit[name]) == "function", "Kit." .. name .. " is gone")
		end
		assert(Kit.Clicked and Kit.Ticked and Kit.Juice and Kit.HEADER == 64, "Kit's signals, Juice and HEADER")
	end)

	test("Kit.card: the Card fill, the Medium radius, PadCard inside, and NO line", function()
		local card = Kit.card({ Name = "Row" })
		expect(card.Name).toBe("Row")
		expect(card.BackgroundColor3).toEqual(Theme.Colors.Card)
		expect(#borders(card)).toBe(0)
		expect(card:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(Theme.Radius.Medium)
		expect(card:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset).toBe(Theme.Space.PadCard)
		expect(Kit.card({ Pad = false }):FindFirstChildOfClass("UIPadding")).toBeNil()
	end)

	test(
		"the three voices: a name is Normal (Body, Ink), a fact is Soft (Caption, InkSoft), Loud is outlined",
		function()
			local name = Kit.name({ Text = "Dew Duck" })
			expect(name.TextSize).toBe(Theme.TextSize.Body)
			expect(name.TextColor3).toEqual(Theme.Colors.Ink)
			expect(name.Font).toBe(Theme.Font)
			expect(name.TextXAlignment).toBe(W.roblox.Enum.TextXAlignment.Left)
			local fact = Kit.fact({ Text = "Bath Room · Quick Soap" })
			expect(fact.TextSize).toBe(Theme.TextSize.Caption)
			expect(fact.TextColor3).toEqual(Theme.Colors.InkSoft)
			expect(fact:FindFirstChild("TextOutline")).toBeNil()
			local loud = Kit.label({ Text = "Team" })
			Kit.voice(loud, "Loud")
			expect(loud.Font).toBe(Theme.DisplayFont)
			expect(loud.TextColor3).toEqual(Theme.Colors.OnColor)
			expect(loud.TextOutline.Enabled).toBe(true)
			Kit.voice(loud, "Soft")
			expect(loud.TextOutline.Enabled).toBe(false)
			expect(loud.TextSize).toBe(18)
		end
	)

	test("Kit.bar: 8 px, navy on the track, gold at MAX, no line and no text inside", function()
		local bar, set = Kit.bar({ Value = 0.25 })
		expect(bar.Size.Y.Offset).toBe(8)
		expect(bar.BackgroundColor3).toEqual(Theme.Colors.Track)
		expect(bar.Fill.BackgroundColor3).toEqual(Theme.Colors.Progress)
		expect(Theme.Colors.Progress).toEqual(Theme.Colors.Header) -- navy, so green only means "collect"
		expect(bar.Fill.Size.X.Scale).toBe(0.25)
		expect(bar.Fill.Visible).toBe(true)
		expect(#borders(bar)).toBe(0)
		for _, child in bar:GetDescendants() do
			assert(child.ClassName ~= "TextLabel", "a bar has no text inside")
		end
		set(1, true)
		expect(bar.Fill.Size.X.Scale).toBe(1)
		expect(bar.Fill.BackgroundColor3).toEqual(Theme.Colors.ProgressMax)
		set(0)
		expect(bar.Fill.Visible).toBe(false)
		expect(bar.Fill.BackgroundColor3).toEqual(Theme.Colors.Progress)
		set(7) -- junk past the end is full, never wider
		expect(bar:GetAttribute("Fraction")).toBe(1)
	end)

	test("Kit.artTile: a Well tile, ONE emoji at 40 px, no line; the State badge comes and goes", function()
		local tile = Kit.artTile({ Icon = "🧼", State = Icons.State.Locked })
		expect(tile.BackgroundColor3).toEqual(Theme.Colors.Well)
		expect(tile.Size.X.Offset).toBe(Theme.Calm.ArtTile)
		expect(tile.Icon.Text).toBe("🧼")
		expect(tile.Icon:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize).toBe(Theme.Emoji.Art)
		expect(#borders(tile)).toBe(0)
		expect(tile.State.Icon.Text).toBe("🔒")
		expect(tile.State.Icon.TextSize).toBe(Theme.Emoji.State)
		Kit.setState(tile, Icons.State.Resting)
		expect(tile.State.Icon.Text).toBe("💤")
		local badges = 0
		for _, child in tile:GetChildren() do
			if child.Name == "State" then
				badges += 1
			end
		end
		expect(badges).toBe(1) -- one per card
		Kit.setState(tile, nil)
		expect(tile:FindFirstChild("State")).toBeNil()
		-- A portrait well: no emoji; a rarity frame is its only line.
		local well = Kit.artTile({ Rarity = "Rare" })
		expect(well:FindFirstChild("Icon")).toBeNil()
		expect(well.RarityFrame.ClassName).toBe("UIStroke")
	end)

	test("Kit.unit: the emoji and its number are two labels, so an emoji is never inside outlined text", function()
		local row, amount = Kit.unit({ Icon = Icons.Unit.Cash, Text = "300", Voice = "Loud", Px = 36 })
		expect(row.Icon.Text).toBe("💰")
		expect(row.Icon:FindFirstChild("TextOutline")).toBeNil()
		expect(amount.Text).toBe("300")
		expect(amount.TextOutline.Enabled).toBe(true)
		expect(amount.TextSize).toBe(36)
		expect(row.Icon.TextSize).toBe(36)
		expect(row:FindFirstChildOfClass("UIListLayout").Padding.Offset).toBe(Theme.Space.Tight)
		local _, soft = Kit.unit({ Icon = Icons.Unit.Level, Text = "Lv 3", Voice = "Soft" })
		expect(soft.TextSize).toBe(18)
		local _, small = Kit.unit({ Icon = Icons.Unit.Stars, Text = "5", Px = 9 })
		expect(small.TextSize).toBe(18) -- never under the floor
	end)

	test("Kit.toggle: a label that never changes and a switch that does; green when on, no line", function()
		local row, set = Kit.toggle({ Label = "Music", On = true })
		expect(row.Label.Text).toBe("Music")
		expect(row:GetAttribute("On")).toBe(true)
		expect(row.Switch.BackgroundColor3).toEqual(Theme.Colors.Collect)
		local onX = row.Switch.Knob.Position.X.Offset
		expect(#borders(row)).toBe(0)
		expect(row.Size.Y.Offset).toBe(56) -- the whole row is the tap target
		set(false)
		expect(row.Label.Text).toBe("Music")
		expect(row:GetAttribute("On")).toBe(false)
		expect(row.Switch.BackgroundColor3).toEqual(Theme.Colors.Disabled)
		assert(row.Switch.Knob.Position.X.Offset < onX, "the knob slides left when off (not colour alone)")
		local _, _ = Kit.toggle({ Label = "Effects" }) -- off unless told
	end)

	test("Secondary and Disabled buttons have no outline; the candy roles and the Icon plate keep theirs", function()
		for _, kind in { "Secondary", "Quiet" } do
			expect(#borders(Kit.button({ Kind = kind, Text = "x" }))).toBe(0)
		end
		for _, kind in { "Primary", "Collect", "Destructive", "Icon" } do
			expect(#borders(Kit.button({ Kind = kind, Text = "x" }))).toBe(1)
		end
		local button = Kit.button({ Kind = "Primary", Text = "Buy" })
		Kit.setEnabled(button, false)
		expect(#borders(button)).toBe(0)
		Kit.setEnabled(button, true)
		expect(#borders(button)).toBe(1)
	end)

	test("Kit.tab: unselected has no plate and no line; selected is navy with white text, no line", function()
		local tab = Kit.iconButton({ Icon = "x", Caption = "Team" })
		Kit.tab(tab, false)
		expect(tab.BackgroundTransparency).toBe(1)
		expect(#borders(tab)).toBe(1) -- the red dot's own line only (it is hidden until there is news)
		expect(borders(tab)[1].Parent.Name).toBe("Dot")
		expect(tab.Caption.TextColor3).toEqual(Theme.Colors.Ink)
		Kit.tab(tab, true, Theme.Colors.Pink)
		expect(tab.BackgroundTransparency).toBe(0)
		expect(tab.BackgroundColor3).toEqual(Theme.Colors.Header)
		expect(tab.Caption.TextColor3).toEqual(Theme.Colors.OnColor)
		expect(#borders(tab)).toBe(1)
		expect(tab.Stripe.BackgroundColor3).toEqual(Theme.Colors.Pink)
	end)

	test("Kit.ring draws nothing when the ability is ready: the beads show only while it recharges", function()
		local holder = Kit.card()
		local set = Kit.ring(holder, Theme.Colors.Progress)
		expect(holder.Ring.Visible).toBe(false) -- before anything is known
		set(1)
		expect(holder.Ring.Visible).toBe(false)
		set(0.4)
		expect(holder.Ring.Visible).toBe(true)
		set(1)
		expect(holder.Ring.Visible).toBe(false)
	end)

	test("Kit.panel: the title is words only, whatever a caller passes", function()
		expect(Kit.panel({ Title = "🛒 Shop" }).Title.Text).toBe("Shop")
		expect(Kit.panel({ Title = "👩‍⚕️ Team" }).Title.Text).toBe("Team")
		expect(Kit.panel({ Title = "Settings" }).Title.Text).toBe("Settings")
		expect(#borders(Kit.panel({ Title = "Shop" }))).toBe(1) -- the panel shell
	end)

	test("Kit.reveal: a door pops in once; already there, nothing happens; false hides it", function()
		local door = Kit.iconButton({ Icon = Icons.Door.Mail, Caption = "Mail" })
		door.Visible = false
		expect(Kit.reveal(door, true)).toBe(true)
		expect(door.Visible).toBe(true)
		expect(Kit.reveal(door, true)).toBe(false)
		expect(Kit.reveal(door, false)).toBe(false)
		expect(door.Visible).toBe(false)
	end)

	-- A screen the menu can sit on (the mock knows a class by its name).
	local function screenWith(): (any, any)
		local screen = W.new("LayerCollector")
		screen.AbsolutePosition = W.roblox.Vector2.new(0, 36)
		screen.AbsoluteSize = W.roblox.Vector2.new(568, 284)
		local more = Kit.more({ Parent = screen })
		more.AbsolutePosition = W.roblox.Vector2.new(400, 96)
		more.AbsoluteSize = W.roblox.Vector2.new(88, 56)
		return screen, more
	end
	local ITEMS = { { Id = "Sell", Text = "Sell" }, { Id = "List", Text = "List" } }

	test("Kit.more is a Quiet text button that says More (no emoji)", function()
		local _, more = screenWith()
		expect(more.Text).toBe("More")
		expect(more.BackgroundTransparency).toBe(1)
		expect(#borders(more)).toBe(0)
		expect(Kit.more({ Text = "Other" }).Text).toBe("Other")
	end)

	test("Kit.menu: one Secondary button per item beside its anchor; a pick closes it and tells the caller", function()
		local screen, more = screenWith()
		local picked: string? = nil
		Kit.menu(more, ITEMS, function(id)
			picked = id
		end)
		local menu = screen.Menu
		expect(menu.Size.X.Offset).toBe(Theme.Calm.MenuWidth)
		expect(menu.Position.X.Offset).toBe(288) -- 400 + 88 - 200
		expect(menu.Position.Y.Offset).toBe(120) -- 96 - 36 + 56 + 4, in the screen's own px
		expect(menu.Item_Sell.Text).toBe("Sell")
		expect(menu.Item_List.Text).toBe("List")
		expect(menu.Item_Sell:GetAttribute("KitKind")).toBe("Secondary") -- nothing candy in the menu
		expect(#borders(menu.Item_Sell)).toBe(0)
		expect(W.bound.KitCloseMenu).toBe(true) -- ButtonB closes it
		menu.Item_List.Activated:Fire()
		expect(picked).toBe("List")
		expect(screen:FindFirstChild("Menu")).toBeNil()
		expect(screen:FindFirstChild("MenuCatcher")).toBeNil()
		expect(W.bound.KitCloseMenu).toBeNil()
	end)

	test("Kit.menu: a tap outside closes it and picks nothing; a second menu closes the first", function()
		local screen, more = screenWith()
		local picks = 0
		local function pick()
			picks += 1
		end
		Kit.menu(more, ITEMS, pick)
		screen.MenuCatcher.Activated:Fire()
		expect(screen:FindFirstChild("Menu")).toBeNil()
		expect(picks).toBe(0)
		local close = Kit.menu(more, ITEMS, pick)
		local other, otherMore = screenWith()
		Kit.menu(otherMore, ITEMS, pick)
		expect(screen:FindFirstChild("Menu")).toBeNil() -- one menu at a time
		assert(other:FindFirstChild("Menu"), "the second menu is open")
		close() -- closing a closed menu is harmless
		assert(other:FindFirstChild("Menu"), "and never closes someone else's")
		expect(W.bound.KitCloseMenu).toBe(true)
	end)

	test("Kit.more with Items opens the menu on a tap (a function is asked each time)", function()
		local screen = W.new("LayerCollector")
		screen.AbsolutePosition = W.roblox.Vector2.new(0, 0)
		screen.AbsoluteSize = W.roblox.Vector2.new(1280, 720)
		local asked = 0
		local got: string? = nil
		local more = Kit.more({
			Parent = screen,
			Items = function()
				asked += 1
				return ITEMS
			end,
			OnPick = function(id)
				got = id
			end,
		})
		more.AbsolutePosition = W.roblox.Vector2.new(600, 300)
		more.AbsoluteSize = W.roblox.Vector2.new(88, 56)
		more.Activated:Fire()
		expect(asked).toBe(1)
		screen.Menu.Item_Sell.Activated:Fire()
		expect(got).toBe("Sell")
		-- No items, no menu.
		local empty = Kit.more({ Parent = screen, Items = {} })
		empty.AbsolutePosition = W.roblox.Vector2.new(600, 300)
		empty.AbsoluteSize = W.roblox.Vector2.new(88, 56)
		empty.Activated:Fire()
		expect(screen:FindFirstChild("Menu")).toBeNil()
	end)
end)

T.describe("The calm template, built for real (Modal loaded whole)", function()
	local W = calmWorld()
	local Modal, Theme = W.Modal, W.Theme

	test("the header: a title in words only, a 48 px ✖ inside the band, the meta as plain Loud text", function()
		local modal = Modal.modal(W.ctx, { Name = "Nurses", Title = "👩‍⚕️ Team", Meta = "3/3" })
		expect(modal.Title.Text).toBe("Team")
		modal.setTitle("📔 Journal")
		expect(modal.Title.Text).toBe("Journal")
		local close = modal.CloseButton
		expect(close.Text).toBe("✖")
		expect(close.Size.X.Offset).toBe(48)
		expect(close.Size.Y.Offset).toBe(48)
		expect(close:FindFirstChildOfClass("UISizeConstraint").MinSize.X).toBe(48)
		expect(close:GetAttribute("KitKind")).toBe("Destructive") -- the only red on the chrome
		-- The meta: no box, no line; white outlined display text on the navy band.
		expect(modal.Meta.Text).toBe("3/3")
		expect(modal.Meta.Visible).toBe(true)
		expect(modal.Meta.BackgroundTransparency).toBe(1)
		expect(#borders(modal.Meta)).toBe(0)
		expect(modal.Meta.Font).toBe(Theme.DisplayFont)
		expect(modal.Meta.TextColor3).toEqual(Theme.Colors.OnColor)
		-- A Unit rides in front of the number as its own plain label (an emoji can't be outlined).
		modal.setMeta("726", W.Icons.Unit.Cash)
		expect(modal.Meta.Text).toBe("726")
		expect(modal.Panel.MetaUnit.Text).toBe("💰")
		expect(modal.Panel.MetaUnit.Visible).toBe(true)
		expect(modal.Panel.MetaUnit:FindFirstChild("TextOutline")).toBeNil()
		modal.setMeta("18%")
		expect(modal.Panel.MetaUnit.Visible).toBe(false)
		modal.setMeta("")
		expect(modal.Meta.Visible).toBe(false)
		expect(modal.Panel.MetaUnit.Visible).toBe(false)
		-- The whole shell has two shape outlines: the panel's and the ✖'s.
		expect(#borders(modal.Root)).toBe(2)
	end)

	test("Modal.tabs: hidden tabs don't show; under two there is no column and the content takes the body", function()
		local modal = Modal.modal(W.ctx, { Name = "Shop", Title = "Shop" })
		local picked = {}
		local tabs = Modal.tabs(modal, {
			{ Id = "Items", Icon = "x", Caption = "Items" },
			{ Id = "Rooms", Icon = "x", Caption = "Rooms", Hidden = true },
			{ Id = "Decor", Icon = "x", Caption = "Decor", Hidden = true },
		}, function(id)
			table.insert(picked, id)
		end)
		expect(tabs.visible()).toEqual({ "Items" })
		expect(tabs.Column.Visible).toBe(false)
		expect(tabs.Content.Position.X.Offset).toBe(0)
		expect(tabs.Content.Size.X.Offset).toBe(0)
		expect(tabs.Buttons.Rooms.Visible).toBe(false)
		-- Rooms unlocks: the column arrives, Items stays selected and nothing is re-picked.
		tabs.setVisible("Rooms", true)
		expect(tabs.visible()).toEqual({ "Items", "Rooms" })
		expect(tabs.Column.Visible).toBe(true)
		assert(tabs.Content.Position.X.Offset > 0, "the content makes room for the column")
		expect(tabs.Buttons.Items:GetAttribute("Selected")).toBe(true)
		expect(picked).toEqual({})
		-- The selected tab goes away: the first one left is selected and the caller is told.
		tabs.select("Rooms")
		tabs.setVisible("Rooms", false)
		expect(picked).toEqual({ "Rooms", "Items" })
		expect(tabs.Buttons.Items:GetAttribute("Selected")).toBe(true)
		expect(tabs.Column.Visible).toBe(false)
		tabs.setVisible("Nope", true) -- an unknown id is ignored
		expect(tabs.visible()).toEqual({ "Items" })
	end)

	test(
		"Modal.tabs: with every tab showing it is the old pattern (the first selected, a column beside the content)",
		function()
			local modal = Modal.modal(W.ctx, { Name = "Book", Title = "Book" })
			local tabs = Modal.tabs(modal, {
				{ Id = "A", Icon = "x", Caption = "A" },
				{ Id = "B", Icon = "x", Caption = "B" },
			}, function() end)
			expect(tabs.Column.Visible).toBe(true)
			expect(tabs.Buttons.A:GetAttribute("Selected")).toBe(true)
			expect(tabs.Buttons.B:GetAttribute("Selected")).toBe(false)
			expect(tabs.Buttons.B.BackgroundTransparency).toBe(1) -- no plate
		end
	)

	test("the confirm: its line sits on a card with no line; one candy button; 'Not now' is flat", function()
		local said = 0
		Modal.confirm(
			W.ctx,
			{ Title = "Sell Dew Duck?", Line = "You get 💰 120", Yes = "Sell", No = "Keep", Kind = "Destructive" },
			function()
				said += 1
			end
		)
		local body = W.playerGui.Modal_Confirm.Root.Panel.Body
		expect(body.Card.Line.Text).toBe("You get 💰 120")
		expect(#borders(body.Card)).toBe(0)
		expect(body.Yes:GetAttribute("KitKind")).toBe("Destructive")
		expect(body.No:GetAttribute("KitKind")).toBe("Secondary")
		expect(body.No.Text).toBe("Keep")
		expect(#borders(body.No)).toBe(0)
		expect(#borders(body)).toBe(1) -- the one candy button
		body.Yes.Activated:Fire()
		body.Yes.Activated:Fire()
		expect(said).toBe(1)
	end)
end)

T.describe("The template in the source (every T6 file)", function()
	test("uirules: no text under 18, no local paintTab/textLimit, radii from tokens, no panel header colour", function()
		local violations = UiRules.check(T6_FILES)
		assert(#violations == 0, "\n" .. UiRules.format(violations))
	end)
	test("every button Kind is a role (no candy kinds: Good, Danger, Pink, Purple, Cyan, Cash, Card)", function()
		local allowed = { Disabled = true }
		for _, role in Juice.ROLES do
			allowed[role] = true
		end
		for _, path in T6_FILES do
			for kind in string.gmatch(code(path), 'Kind = "(%w+)"') do
				assert(allowed[kind], path .. ": Kind " .. kind .. " is not a role")
			end
		end
	end)
	test("every panel is on THE template: Hud.modal (or Modal.modal), no Accent", function()
		for _, name in PANELS do
			local body = code("src/client/UI/" .. name .. ".luau")
			assert(
				string.find(body, "Hud.modal(", 1, true) or string.find(body, "Modal.modal(", 1, true),
				name .. " builds its own shell"
			)
			expect(count(body, "Accent")).toBe(0)
		end
	end)
	test("the tabbed panels use THE tab pattern (Modal.tabs: Badges' row is now the column)", function()
		for _, name in { "Shop", "BookPanel", "Boards", "BadgeBook", "AdminPanel" } do
			local body = code("src/client/UI/" .. name .. ".luau")
			expect(count(body, "Modal.tabs(")).toBe(1)
			expect(count(body, "Hud.fitTabs(")).toBe(0)
		end
	end)
	test("nothing loud points at spending: the Shop and the Day Report never shine or breathe", function()
		for _, name in { "Shop", "DayReportPanel", "BookPanel", "Boards", "BadgeBook", "AdminPanel" } do
			local body = code("src/client/UI/" .. name .. ".luau")
			expect(count(body, "Kit.shine(")).toBe(0)
			expect(count(body, "Kit.breathing(")).toBe(0)
		end
		-- The Shop's Buy and Level up are Primary; the Day Report's 🛒 is its one Primary.
		local shop = code("src/client/UI/Shop.luau")
		assert(string.find(shop, 'Buy = { Role = "Primary"', 1, true), "Buy is Primary")
		assert(string.find(shop, 'Name = "LevelUp",\n\t\tKind = "Primary",', 1, true), "Level up is Primary")
		local day = code("src/client/UI/DayReportPanel.luau")
		expect(count(day, 'Kind = "Primary"')).toBe(1)
	end)
	test("the shines and breaths left are on Collect buttons only (claims, Open!, Tap!)", function()
		for _, name in { "Mailbox", "PlayGifts", "MiniGames" } do
			local body = code("src/client/UI/" .. name .. ".luau")
			assert(count(body, 'Kind = "Collect"') >= count(body, "Kit.shine("), name .. ": a shine on a non-Collect")
		end
	end)
	test("BadgeBook's cheer goes through THE notice stack (the bus Banner), not its own banner", function()
		local body = code("src/client/UI/BadgeBook.luau")
		assert(string.find(body, 'ctx.fire("Banner", banner)', 1, true), "the cheer is a bus Banner")
		expect(count(body, "Kit.screen(")).toBe(0)
		expect(count(body, "Kit.rays(")).toBe(0)
	end)
	test("the Day Report's count is Hero text", function()
		local body = code("src/client/UI/DayReportPanel.luau")
		assert(string.find(body, "Kit.textLimit(cured, Theme.TextSize.Hero)", 1, true), "the count at Hero")
	end)
	test("the admin resets are Destructive and ask THE confirm first", function()
		local body = code("src/client/UI/AdminPanel.luau")
		for _, action in { "RestartTutorial", "Rebirth", "ResetDaily" } do
			assert(
				string.find(body, 'Kind = "Destructive",%s*Action = "' .. action .. '"')
					or string.find(body, 'Kind = "Destructive", Action = "' .. action .. '"', 1, true),
				action .. " is not Destructive"
			)
		end
		assert(string.find(body, "Hud.confirm(ctx,", 1, true), "resets go through Hud.confirm")
	end)
end)

T.describe("MiniGames on the template (§B8)", function()
	local body = code("src/client/UI/MiniGames.luau")
	test("THE modal: Layer Panel, HudMode Game, no ✖, a dim that never closes it", function()
		assert(string.find(body, "Modal.modal(ctx, {", 1, true), "the card is Modal.modal")
		assert(string.find(body, 'Layer = "Panel"', 1, true), "Layer Panel")
		assert(string.find(body, 'HudMode = "Game"', 1, true), "HudMode Game")
		assert(string.find(body, "CloseButton = false", 1, true), "no ✖")
		assert(string.find(body, "DimCloses = false", 1, true), "no dim-close")
		expect(count(body, "Kit.screen(")).toBe(0) -- the hand-built shell is gone
	end)
	test("pad prompts are the pad's own picture: never 🅰️", function()
		expect(count(body, "🅰️")).toBe(0)
		assert(string.find(body, "GetImageForKeyCode(Enum.KeyCode.ButtonA)", 1, true), "GetImageForKeyCode")
	end)
	test("stage() is real now (no STUB left)", function()
		expect(count(source("src/client/UI/MiniGames.luau"), "STUB")).toBe(0)
		assert(string.find(body, "return v.Stage", 1, true), "stage() returns the stage")
	end)
	test("v2 keeps working: auto PERFECT, Ease and Triage are all still there", function()
		for _, needle in
			{
				"playAuto(",
				"Pure.eased(ctx.Config.MiniGame, session.Ease)",
				"runTriage(ctx, v, run, triage, answeredAt)",
				"ctx.Remotes.Triage",
			}
		do
			assert(string.find(body, needle, 1, true), "missing: " .. needle)
		end
	end)
	test("the tutorial never sees a clock run down (Pure.drainBar)", function()
		expect(MiniPure.drainBar(0.4, true)).toBeNil()
		expect(MiniPure.drainBar(0.4, false)).toBe(0.4)
		expect(MiniPure.drainBar(-1, false)).toBe(0)
		expect(MiniPure.drainBar(3, false)).toBe(1)
		expect(MiniPure.drainBar(0 / 0, false)).toBe(0)
		expect(MiniPure.drainBar("x", false)).toBe(0)
		assert(string.find(body, "HideDrain = TutorialLogic.active(ctx.State.Tutorial)", 1, true), "wired")
	end)
end)
