--!nocheck
-- T1 of the calm UI build (docs/plan/2026-11-17-ui-direction.md §4 row 4, §5 "T1 Nurses"; Joshua's rulings
-- memory-20261117-006 "simple, especially at the start" and -007: one main button per Team card, Sell and List behind
-- "More" once you own 2 nurses, titles in words, navy progress bars). Run from game/ with the rest:  lune run tests/run
--   · the ratchet: UI/NursePanel.luau has NO calm-rule fault left (TitleEmoji, LabelEmoji, LeadEmoji, TypedEmoji,
--     SpaceLiteral, StrokeBudget all 0; the two outlines left, the nurse cap and the stamp over the 3D world, carry
--     the allow comment), and the old hard rules still hold
--   · THE TEAM CARD (Pure.teamCard): exactly one filled button (the job), More only from 2 nurses and never for a
--     rebirth-only nurse, at most 2 Soft facts with at most one emoji each, the bar only once the first XP is earned,
--     the ability only once it can differ, 💤 as the State badge of a resting nurse whose button reads "Pick a job"
--   · R0, "a fresh save is simple" (Pure.visible): a Lv 1 save sees the Team tab alone (no Journal tab, no Agency or
--     Market link); a rich save still sees everything, so nothing is lost
--   · the source draws what the pure block decides: Kit.card, Kit.bar, Kit.more, Kit.setState, Kit.artTile

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local UiRules = require("./uirules")

local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local JobsLogic = require("../src/shared/Logic/Jobs")
local AbilitiesLogic = require("../src/shared/Logic/Abilities")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Jobs = require("../src/shared/Data/Jobs")
local Departments = require("../src/shared/Data/Departments")
local Abilities = require("../src/shared/Data/Abilities")
local Config = require("./config")

local PATH = "src/client/UI/NursePanel.luau"

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(path: string, env: { [string]: any }): any
	local text = source(path)
	local first = string.find(text, "-- PURE-BEGIN", 1, true)
	local last = string.find(text, "-- PURE-END", 1, true)
	assert(first and last and last > first, "no PURE block in " .. path)
	local block = string.sub(text, first, last - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = env })()
end

local Icons = UiRules.Icons
local BeltPure = pureBlock("src/client/UI/BeltView.luau", {
	BeltLogic = BeltLogic,
	NurseLogic = NurseLogic,
	TutorialLogic = TutorialLogic,
})
local Pure = pureBlock(PATH, {
	BeltPure = BeltPure,
	Icons = Icons,
	NurseLogic = NurseLogic,
	JobsLogic = JobsLogic,
	AbilitiesLogic = AbilitiesLogic,
})

local FILLED = { Primary = true, Collect = true, Secondary = true, Destructive = true }

local function eq(actual: any, expected: any)
	expect(actual).toEqual(expected)
end

local function own(ids: { string }, fields: { [string]: any }?): { [string]: any }
	local out = {}
	for _, id in ids do
		local entry = { Level = 1, XP = 0, Copies = 1, Job = "" }
		for key, value in fields or {} do
			entry[key] = value
		end
		out[id] = entry
	end
	return out
end

local function snap(fields: { [string]: any }?): any
	local f = fields or {}
	local rebirth = f.Rebirth or {}
	return {
		Level = f.Level or 1,
		Rooms = f.Rooms or {},
		Nurses = f.Nurses or {},
		NurseIndex = f.NurseIndex or {},
		Rebirth = { Count = rebirth.Count or 0, Pending = rebirth.Pending or {} },
	}
end

-- A Team card as the panel asks for it (UI/NursePanel renderTeamCard's info).
local function card(nurseId: string, entry: any, extra: { [string]: any }?): any
	local info = {
		Level = 1,
		Jobs = Jobs,
		Departments = Departments,
		Abilities = Abilities,
		Cfg = Config,
		Roster = Nurses,
		LevelCap = NurseLogic.levelCap(0, Config),
		Resting = false,
		Owned = 1,
		Listed = false,
		Depts = 1,
		Fired = false,
		News = nil,
	}
	for key, value in extra or {} do
		info[key] = value
	end
	return Pure.teamCard(nurseId, entry, rawget(Nurses, nurseId), info)
end

local function filled(view: any): number
	local n = 0
	for _, button in view.Buttons do
		if FILLED[button.Kind] then
			n += 1
		end
	end
	return n
end

T.describe("T1 Nurses: the calm rules are locked at 0", function()
	test("UI/NursePanel.luau: no calm-rule fault left (the ratchet at 0 for every rule)", function()
		local over = UiRules.ratchet({ PATH }, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
		eq(#UiRules.calm({ PATH }), 0)
	end)
	test("the old hard rules still hold (text floor, corners, helpers, header colour)", function()
		local faults = UiRules.check({ PATH })
		assert(#faults == 0, "\n" .. UiRules.format(faults))
	end)
	test("the two outlines left say why (the nurse cap, the stamp over the 3D world)", function()
		local allowed = 0
		for line in string.gmatch(source(PATH), "[^\n]+") do
			if string.find(line, "Kit.stroke(", 1, true) then
				assert(
					string.find(line, "uirules: allow StrokeBudget (", 1, true),
					"an outline without its reason: " .. line
				)
				allowed += 1
			end
		end
		eq(allowed, 2)
	end)
end)

T.describe("T1 Nurses: THE TEAM CARD (Pure.teamCard; memory-20261117-007)", function()
	local fresh = { Level = 1, XP = 0, Copies = 1, Job = "" }

	test("a fresh Lv 1 nurse, your only one: portrait, name, level, ONE button; no More, no bar, no facts", function()
		local view = card("PuffPup", fresh)
		eq(view.Name, "Puff Pup")
		eq(view.Level, "Lv 1")
		eq(view.Job, "🧪 Maker")
		eq(view.Buttons, { { Id = "Job", Kind = "Secondary" } })
		eq(filled(view), 1)
		eq(view.More, false)
		eq(view.Items, {})
		eq(view.Bar, false)
		eq(view.Facts, {})
		eq(view.State, nil)
		eq(view.Ring, false)
	end)

	test("Sell and List go behind More once you own 2 nurses (still one filled button)", function()
		local view = card("PuffPup", fresh, { Owned = 2 })
		eq(view.More, true)
		eq(view.Items, { { Id = "Sell", Text = "Sell" }, { Id = "List", Text = "List" } })
		eq(view.Buttons, { { Id = "Job", Kind = "Secondary" }, { Id = "More", Kind = "Quiet" } })
		eq(filled(view), 1)
		for _, item in view.Items do
			eq(Icons.count(item.Text), 0)
		end
	end)

	test("a listed nurse: More reaches its listing (even alone), and one Soft line says so", function()
		local view = card("PuffPup", fresh, { Owned = 1, Listed = true })
		eq(view.More, true)
		eq(view.Items[2], { Id = "List", Text = "See listing" })
		eq(view.Facts, { "On the Market" })
	end)

	test("a rebirth-only nurse never gets More: it stays with you", function()
		local view = card("FounderFennec", fresh, { Owned = 4 })
		eq(view.More, false)
		eq(view.Facts, { "Stays with you" })
		eq(filled(view), 1)
	end)

	test("a resting nurse: 💤 as the State badge, the button reads Pick a job, no ring", function()
		local view = card("PuffPup", { Level = 3, XP = 4, Copies = 3, Job = "Rest" }, { Resting = true, Owned = 4 })
		eq(view.State, Icons.State.Resting)
		eq(view.Job, "Pick a job")
		eq(view.Resting, true)
		eq(view.Ring, false)
		eq(filled(view), 1)
	end)

	test("the job it waits for is a Soft line, never inside the button", function()
		local view = card("PuffPup", { Level = 1, XP = 0, Copies = 1, Job = "Porter" })
		eq(view.Job, "🧪 Maker")
		eq(view.Facts, { "Porter opens at 🏥 Lv 2" })
	end)

	test(
		"each fact shows once it can differ: the bar (first XP), the specialty (2 departments), the ability",
		function()
			local xp = card("DewDuck", { Level = 1, XP = 3, Copies = 1, Job = "" })
			eq(xp.Bar, true)
			eq(xp.Facts, {})
			local depts = card("DewDuck", fresh, { Depts = 2 })
			eq(depts.Facts, { "Bath Room" })
			local fired = card("DewDuck", fresh, { Depts = 2, Fired = true })
			local ability = rawget(Abilities, rawget(Nurses, "DewDuck").Ability).Name
			eq(fired.Facts, { "Bath Room · " .. ability })
			eq(fired.Ring, true)
			-- a levelled nurse has surely worked: its ability shows, with its tier from Lv 5
			local five = card("DewDuck", { Level = 5, XP = 0, Copies = 5, Job = "" }, { Depts = 2 })
			eq(five.Facts, { "Bath Room · " .. ability .. "+" })
			eq(five.Bar, true)
			-- a new card shows its XP count with the rest
			local new = card("DewDuck", { Level = 2, XP = 7, Copies = 2, Job = "" }, { Depts = 2, News = "Level" })
			eq(new.Facts, { "Bath Room · " .. ability .. " · 7/" .. NurseLogic.xpToNext(2) .. " XP" })
		end
	)

	test("every nurse, every state: one filled button, at most 2 facts, at most one emoji per label", function()
		for _, nurseId in Nurses.Order do
			for _, entry in
				{
					fresh,
					{ Level = 1, XP = 9, Copies = 1, Job = "Porter" },
					{ Level = 5, XP = 3, Copies = 5, Job = "Healer" },
					{ Level = 10, XP = 0, Copies = 9, Job = "Rest" },
				}
			do
				for _, extra in
					{
						{},
						{ Owned = 2, Depts = 3, Fired = true, News = "Hired" },
						{ Owned = 5, Resting = true, Listed = true, Depts = 8, Level = 3 },
						{ Owned = 3, Listed = true, Fired = true, News = "Level", Level = 2 },
					}
				do
					local view = card(nurseId, entry, extra)
					local where = nurseId .. " " .. tostring(entry.Job)
					eq(filled(view), 1)
					assert(#view.Facts <= 2, where .. ": more than 2 facts")
					assert(Icons.count(view.Job) <= 1, where .. ": " .. view.Job)
					assert(Pure.words(view.Job) <= 6, where .. ": " .. view.Job)
					for _, fact in view.Facts do
						assert(fact ~= "", where .. ": an empty fact")
						assert(Icons.count(fact) <= 1, where .. ": " .. fact)
					end
					eq(Icons.count(view.Level), 0)
					if view.More then
						assert(extra.Owned and extra.Owned >= 2 or extra.Listed, where .. ": More with one nurse")
					end
				end
			end
		end
	end)
end)

T.describe("T1 Nurses: R0, a fresh save is simple (Pure.visible)", function()
	local order = Rarities.Order
	local function tabsShown(view: any): { string }
		local out = {}
		for _, id in Pure.tabIds(order, true) do
			if view.Tabs[id] then
				table.insert(out, id)
			end
		end
		return out
	end

	test("a brand-new Lv 1 save: the Team tab alone, no Agency, no Market", function()
		local view = Pure.visible(snap(), Nurses, order, Config, nil)
		eq(tabsShown(view), { "Team" })
		eq(view.Agency, false)
		eq(view.Market, false)
	end)

	test("one nurse hired, one rarity seen: still the Team alone (a Journal tab needs a second rarity)", function()
		local state = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", MintMouse = "Seen" } })
		local view = Pure.visible(state, Nurses, order, Config, nil)
		eq(tabsShown(view), { "Team" })
		eq(view.Agency, false)
		eq(view.Market, false)
	end)

	test("a second rarity seen: a tab for each rarity seen, and only those", function()
		local state = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", JamJelly = "Seen" } })
		eq(tabsShown(Pure.visible(state, Nurses, order, Config, nil)), { "Team", "Common", "Epic" })
	end)

	test("the Agency link: once the roster is full, a nurse has left you, or this session showed it", function()
		local full = snap({ Nurses = own({ "PuffPup", "MintMouse", "BeanBear" }) })
		eq(Pure.visible(full, Nurses, order, Config, nil).Agency, true)
		local two = snap({ Nurses = own({ "PuffPup", "MintMouse" }) })
		eq(Pure.visible(two, Nurses, order, Config, nil).Agency, false)
		eq(Pure.visible(two, Nurses, order, Config, { Agency = true }).Agency, true)
		local sold = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", MintMouse = "Hired" } })
		local view = Pure.visible(sold, Nurses, order, Config, nil)
		eq(view.Agency, true)
		eq(view.Market, true) -- a nurse left: you have used the Agency or the Market
	end)

	test("the Market link: once the Agency was opened, or a nurse of yours is listed", function()
		local two = snap({ Nurses = own({ "PuffPup", "MintMouse" }) })
		eq(Pure.visible(two, Nurses, order, Config, nil).Market, false)
		eq(Pure.visible(two, Nurses, order, Config, { AgencyOpened = true }).Market, true)
		eq(Pure.visible(two, Nurses, order, Config, { Listed = true }).Market, true)
	end)

	test("a rich save (a branch, a full roster, many rarities) still shows everything", function()
		local index = {}
		for _, nurseId in Nurses.Order do
			index[nurseId] = "Seen"
		end
		local ids = { "PuffPup", "JamJelly", "MintMouse", "BeanBear" }
		for _, id in ids do
			index[id] = "Hired"
		end
		local state = snap({
			Level = 5,
			Nurses = own(ids, { Level = 6, XP = 3 }),
			NurseIndex = index,
			Rebirth = { Count = 1 },
		})
		local view = Pure.visible(state, Nurses, order, Config, { AgencyOpened = true })
		local all = { "Team" }
		for _, rarity in order do
			table.insert(all, rarity)
		end
		table.insert(all, "Branch")
		eq(tabsShown(view), all)
		eq(view.Agency, true)
		eq(view.Market, true)
	end)
end)

T.describe("T1 Nurses: the source draws what the pure block decides", function()
	local text = source(PATH)
	local function has(needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	test("the calm parts: Kit.card, Kit.bar, Kit.more, Kit.setState, Kit.artTile, Kit.fact, Kit.name", function()
		for _, part in
			{ "Kit.card(", "Kit.bar(", "Kit.more(", "Kit.setState(", "Kit.artTile(", "Kit.fact(", "Kit.name(" }
		do
			assert(has(part), "NursePanel doesn't use " .. part)
		end
		assert(has("Pure.teamCard("), "the Team card isn't drawn from Pure.teamCard")
		assert(has("Pure.visible("), "the panel doesn't ask Pure.visible what shows")
		assert(has("tabs.setVisible("), "the tabs don't follow Pure.visible")
	end)

	test("no hand-built chip, pill, plate or tilted ribbon is left", function()
		for _, gone in { "local function chip(", "Rotation = -8", "Rotation = -10", "XpFill", "LevelBadge" } do
			assert(not has(gone), "still in NursePanel: " .. gone)
		end
	end)

	test("the titles are words and the meta has no emoji", function()
		eq(Pure.TEXT.TitleTeam, "Team")
		eq(Pure.TEXT.TitleJournal, "Journal")
		eq(Icons.count(Pure.metaText(42)), 0)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The panel built for real (no Studio here): tests/Chrome.spec's calm world (tests/worldmock Instances, stand-in
-- services, ReduceEffects so nothing tweens), with Kit, Modal and NursePanel loaded WHOLE and Hud / BeltView
-- stubbed. It catches nil calls and wrong structure in the builders, not a misspelt property (the mock stores any).
------------------------------------------------------------------------------------------------------------------
local World = require("./worldmock")

local function panelWorld(): any
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
	local workspace = {
		GetAttribute = function()
			return nil
		end,
		GetAttributeChangedSignal = function()
			return signal()
		end,
		FindFirstChild = function()
			return nil
		end,
		GetServerTimeNow = function()
			return 0
		end,
	}
	local services = {
		Players = { LocalPlayer = player },
		GuiService = { ReducedMotionEnabled = false, SelectedObject = nil },
		UserInputService = { PreferredInput = roblox.Enum.PreferredInput.Touch },
		Workspace = workspace,
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
	local SHARED = {
		Palette = "src/shared/Palette.luau",
		Signal = "src/shared/Signal.luau",
		Types = "src/shared/Types.luau",
		Data = { Rarities = "src/shared/Data/Rarities.luau" },
		Logic = {
			Belt = "src/shared/Logic/Belt.luau",
			Nurse = "src/shared/Logic/Nurse.luau",
			Jobs = "src/shared/Logic/Jobs.luau",
			Abilities = "src/shared/Logic/Abilities.luau",
			Tutorial = "src/shared/Logic/Tutorial.luau",
		},
	}
	local function folder(map: any): any
		return {
			WaitForChild = function(_, name: string)
				local found = map[name]
				assert(found, "panelWorld has no Shared." .. name)
				return if type(found) == "table" then folder(found) else found
			end,
		}
	end
	local modules: { [any]: any } = {}
	local UI: { [string]: any } = {
		Theme = "src/client/UI/Theme.luau",
		Icons = "src/client/UI/Icons.luau",
		Kit = "src/client/UI/Kit.luau",
		Modal = "src/client/UI/Modal.luau",
	}
	local WHOLE = { ["/UI/Kit.luau"] = true, ["/UI/Modal.luau"] = true, ["/UI/NursePanel.luau"] = true }
	local function load(path: any): any
		if type(path) == "table" then
			return path -- a stub (Hud, BeltView)
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
					return assert(services[name], "panelWorld has no " .. name)
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
	local Modal = load(UI.Modal)
	local popped = {}
	UI.Hud = {
		modal = Modal.modal,
		portrait = function()
			return new("Frame")
		end,
		ask = function()
			return false, ""
		end,
		shake = function() end,
		pop = function(gui)
			table.insert(popped, gui)
		end,
		sound = function() end,
		target = function()
			return nil
		end,
	}
	UI.BeltView = { Pure = BeltPure }
	return {
		Kit = Kit,
		Modal = Modal,
		NursePanel = load("src/client/UI/NursePanel.luau"),
		playerGui = playerGui,
		roblox = roblox,
	}
end

-- A client ctx: the bus (fire reaches on), the Snapshot, toasts.
local function panelCtx(state: any): any
	local handlers: { [string]: { (...any) -> () } } = {}
	local ctx
	ctx = {
		Data = {
			Nurses = Nurses,
			Rarities = Rarities,
			Jobs = Jobs,
			Departments = Departments,
			Abilities = Abilities,
			Decor = require("../src/shared/Data/Decor"),
		},
		Config = Config,
		State = state,
		Remotes = { SetJob = {}, ClaimBranchNurse = {}, GetMarket = {} },
		fired = {},
		toasts = {},
		on = function(name: string, fn: (...any) -> ())
			handlers[name] = handlers[name] or {}
			table.insert(handlers[name], fn)
		end,
		onState = function(fn)
			ctx.on("__state", fn)
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
	return ctx
end

local function find(root: any, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name then
			return node
		end
	end
	return nil
end

-- Shown on screen: it and every GuiObject above it inside the panel are Visible.
local function shown(node: any): boolean
	local at = node
	while at and at.ClassName ~= "Folder" do
		if at.Visible == false then
			return false
		end
		at = at.Parent
	end
	return true
end

local function buttonsIn(root: any): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node.ClassName == "TextButton" and node:GetAttribute("KitKind") ~= nil and shown(node) then
			table.insert(out, node)
		end
	end
	return out
end

T.describe("T1 Nurses: the panel built for real (Kit, Modal and NursePanel whole)", function()
	test("a fresh save: the Team page alone, no tab column, no links, the empty card", function()
		local W = panelWorld()
		local ctx = panelCtx(snap())
		W.NursePanel.init(ctx)
		ctx.fire("Open", "Nurses")
		local team = nil
		for _, node in W.playerGui:GetDescendants() do
			if node.ClassName == "ScrollingFrame" and node.Name == "Team" then
				team = node
			end
		end
		assert(team and team.Visible, "the Team page shows")
		expect(find(team, "Links").Visible).toBe(false)
		expect(find(team, "Empty").Visible).toBe(true)
		for _, rarity in Rarities.Order do
			expect(find(W.playerGui, "Tab_" .. rarity).Visible).toBe(false)
		end
		ctx.fire("ModalClosed", "Nurses")
	end)

	test("one nurse: its card has the one job button and nothing else to press", function()
		local W = panelWorld()
		local ctx = panelCtx(snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired" } }))
		W.NursePanel.init(ctx)
		ctx.fire("Open", "Nurses")
		local cardFrame = find(find(W.playerGui, "Cards"), "PuffPup")
		assert(cardFrame, "PuffPup's Team card")
		local buttons = buttonsIn(cardFrame)
		expect(#buttons).toBe(1)
		expect(buttons[1].Name).toBe("Job")
		expect(buttons[1]:GetAttribute("KitKind")).toBe("Secondary")
		expect(buttons[1].Text).toBe("🧪 Maker")
		expect(find(cardFrame, "Xp").Visible).toBe(false)
		expect(find(cardFrame, "More").Visible).toBe(false)
		expect(find(cardFrame, "NurseName").Text).toBe("Puff Pup")
		-- the one button opens the job picker: a row per job, ✅ on the one it works, the Lv 2 jobs gated
		buttons[1].Activated:Fire()
		local jobs = nil
		for _, node in W.playerGui:GetDescendants() do
			if node.ClassName == "ScrollingFrame" and node.Name == "Jobs" then
				jobs = node
			end
		end
		assert(jobs, "the job picker's list")
		expect(find(find(jobs, "Maker"), "Caption").Text).toBe(Icons.State.Done)
		expect(find(find(jobs, "Porter"), "Caption").Text).toBe("🏥 Lv 2")
		expect(find(find(jobs, "Healer"), "JobName").Text).toBe("Healer  +40%")
		ctx.fire("ModalClosed", "Nurses")
	end)

	test("two nurses and one resting: More shows; 💤 on the resting portrait, Pick a job", function()
		local W = panelWorld()
		local nurses = own({ "PuffPup", "MintMouse", "BeanBear" }, { Level = 2, XP = 5 })
		nurses.DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "Rest" }
		local index = { PuffPup = "Hired", MintMouse = "Hired", BeanBear = "Hired", DewDuck = "Hired" }
		local ctx = panelCtx(snap({ Nurses = nurses, NurseIndex = index }))
		W.NursePanel.init(ctx)
		ctx.fire("Open", "Nurses")
		local cards = find(W.playerGui, "Cards")
		local puff = find(cards, "PuffPup")
		local filledCount = 0
		for _, button in buttonsIn(puff) do
			if FILLED[button:GetAttribute("KitKind")] then
				filledCount += 1
			end
		end
		expect(filledCount).toBe(1)
		expect(find(puff, "More").Visible).toBe(true)
		expect(find(puff, "More"):GetAttribute("KitKind")).toBe("Quiet")
		expect(find(puff, "Xp").Visible).toBe(true)
		local dew = find(cards, "DewDuck")
		expect(find(dew, "Job").Text).toBe("Pick a job")
		local badge = find(find(dew, "Face"), "State")
		assert(badge, "the resting nurse wears its State badge")
		expect(find(badge, "Icon").Text).toBe(Icons.State.Resting)
		-- the roster is full: the Agency link shows (the Market waits for the Agency to be opened)
		local links = find(W.playerGui, "Links")
		expect(links.Visible).toBe(true)
		expect(find(links, "Agency").Visible).toBe(true)
		expect(find(links, "Market").Visible).toBe(false)
		ctx.fire("Open", "Agency")
		ctx.fire("__state", ctx.State)
		expect(find(links, "Market").Visible).toBe(true)
		ctx.fire("ModalClosed", "Nurses")
	end)

	test("two rarities seen: the Journal's tabs arrive and a page draws without an outline on its cards", function()
		local W = panelWorld()
		local ctx = panelCtx(snap({
			Nurses = own({ "PuffPup" }),
			NurseIndex = { PuffPup = "Hired", JamJelly = "Seen" },
		}))
		W.NursePanel.init(ctx)
		ctx.fire("Open", "Nurses", "Common")
		local page = find(W.playerGui, "Common")
		assert(page and page.Visible, "the Common page shows")
		local puff = find(page, "PuffPup")
		expect(find(puff, "Info").Text).toBe("Lv 1 · Maker")
		-- R2: no shape outline on the page but a candy button's (Collect) and the rarity frame / the nurse cap.
		local CANDY = { Primary = true, Collect = true, Destructive = true }
		local strokes = 0
		for _, node in page:GetDescendants() do
			if
				node.ClassName == "UIStroke"
				and node.Enabled ~= false
				and node.ApplyStrokeMode ~= W.roblox.Enum.ApplyStrokeMode.Contextual
				and node.Name ~= "TextOutline"
				and node.Name ~= "RarityFrame"
				and node.Parent.Name ~= "Cap"
				and not CANDY[node.Parent:GetAttribute("KitKind")]
			then
				strokes += 1
			end
		end
		expect(strokes).toBe(0)
		ctx.fire("ModalClosed", "Nurses")
	end)
end)
