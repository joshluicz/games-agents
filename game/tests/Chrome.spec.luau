--!strict
-- The chrome (look build plan T6, §B8): the one modal template, the button roles, the one tab and the one text fit,
-- checked on the shipped code. Kit.Juice and Modal.Pure are loaded from their marked blocks; Kit.textLimit runs on
-- its own with a stand-in Instance; the rest reads the source of every T6 file (uirules and the template's rules).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local UiRules = require("./uirules")
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
		expect(Juice.LOOKS.Secondary.Stroke).toBe("Fine")
		expect(Juice.LOOKS.Quiet.Clear).toBe(true) -- no fill ...
		expect(Juice.LOOKS.Quiet.Stroke).toBeNil() -- ... and no outline: a link
		expect(Juice.LOOKS.Icon.Fill).toBe("Plate") -- the white plate ...
		expect(Juice.LOOKS.Icon.Stroke).toBe("Bold") -- ... with the Bold outline
		expect(Juice.LOOKS.Disabled.Fill).toBe("Disabled")
		expect(Juice.LOOKS.Disabled.Text).toBe("DisabledText")
		expect(Juice.look("Good")).toBe(Juice.LOOKS.Collect)
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
			Title = "⏭️ Skip?",
			Line = "You can replay it any time from ⚙️",
			Yes = "⏭️ Skip",
		})
		expect(c.No).toBe("Not now")
		expect(c.Focus).toBe("No")
		expect(c.Kind).toBe("Primary")
		expect(c.Hold).toBe(0)
		expect(c.Line).toBe("You can replay it any time from ⚙️")
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
	test("a tab fits a one-word caption at the 18 px floor (about 10 px a letter)", function()
		for _, caption in { "Upgrades", "Hospital", "Patients", "Stations", "Branches" } do
			assert(#caption * 10 <= ModalPure.TAB_WIDTH, caption .. " is wider than a tab")
		end
		assert(ModalPure.TAB_WIDTH >= 56, "a tab is at least the 56 px tap minimum")
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
