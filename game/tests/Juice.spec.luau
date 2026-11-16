--!strict
-- UI juice helpers (depth-update build plan T6): Kit.Juice and UI/Celebrate's Words. Both live in client files
-- (they need Roblox APIs around them), so this spec loads only their pure blocks, straight from the real source:
-- Kit.luau between "-- BEGIN JUICE" and "-- END JUICE", Celebrate.luau between "-- BEGIN PURE" and "-- END PURE".

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

-- Run from game/ (lune run tests/run) or from the repo root.
local root = if fs.isFile("src/client/UI/Kit.luau") then "." else "game"

local function block(path: string, startMark: string, endMark: string, name: string): any
	local full = root .. "/" .. path
	local source = fs.readFile(full)
	local first = string.find(source, startMark, 1, true)
	local last = string.find(source, endMark, 1, true)
	assert(first and last, "markers missing in " .. path)
	return luau.load(string.sub(source, first, last - 1) .. "\nreturn " .. name, { debugName = full })()
end

local function dataModule(name: string): any
	local full = root .. "/src/shared/Data/" .. name .. ".luau"
	return luau.load(fs.readFile(full), { debugName = full })()
end

local Juice = block("src/client/UI/Kit.luau", "-- BEGIN JUICE", "-- END JUICE", "Juice")
local Words = block("src/client/UI/Celebrate.luau", "-- BEGIN PURE", "-- END PURE", "Words")
local Nurses = dataModule("Nurses")
local Rarities = dataModule("Rarities")
local Levels = dataModule("Levels")

local function near(a: number, b: number, eps: number): boolean
	return math.abs(a - b) <= eps
end

local STEPS = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } }

T.describe("Juice", function()
	test("countSeconds: explicit seconds win, never negative", function()
		expect(Juice.countSeconds(0, 100, 0.25)).toBe(0.25)
		expect(Juice.countSeconds(0, 100, 0)).toBe(0)
		expect(Juice.countSeconds(0, 100, -3)).toBe(0)
	end)
	test("countSeconds: nothing to roll is 0", function()
		expect(Juice.countSeconds(5, 5)).toBe(0)
		expect(Juice.countSeconds(0, 0 / 0)).toBe(0)
	end)
	test("countSeconds: grows with the jump, between 0.3 and 1.4", function()
		local small, mid, big = Juice.countSeconds(0, 1), Juice.countSeconds(0, 100), Juice.countSeconds(0, 1e6)
		expect(near(small, 0.396, 0.01)).toBeTruthy()
		expect(near(mid, 0.6, 0.01)).toBeTruthy()
		expect(small < mid and mid < big).toBeTruthy()
		expect(Juice.countSeconds(1e6, 0)).toBe(big)
		expect(Juice.countSeconds(0, 1e30)).toBe(1.4)
		expect(Juice.countSeconds(0, 1, nil, 0.1)).toBe(0.3)
	end)
	test("ease: clamped, ends on 0 and 1, fast start", function()
		expect(Juice.ease(0)).toBe(0)
		expect(Juice.ease(1)).toBe(1)
		expect(Juice.ease(-2)).toBe(0)
		expect(Juice.ease(3)).toBe(1)
		expect(Juice.ease(0.5) > 0.9).toBeTruthy()
	end)
	test("coins: 0 for nothing, 3..10 by size", function()
		expect(Juice.coins(0)).toBe(0)
		expect(Juice.coins(-5)).toBe(0)
		expect(Juice.coins(0 / 0)).toBe(0)
		expect(Juice.coins(1)).toBe(3)
		expect(Juice.coins(18)).toBe(5)
		expect(Juice.coins(100)).toBe(7)
		expect(Juice.coins(1000)).toBe(9)
		expect(Juice.coins(1e9)).toBe(10)
	end)
	test("clock: m:ss, never negative", function()
		expect(Juice.clock(0)).toBe("0:00")
		expect(Juice.clock(5.9)).toBe("0:05")
		expect(Juice.clock(65)).toBe("1:05")
		expect(Juice.clock(-4)).toBe("0:00")
		expect(Juice.clock(0 / 0)).toBe("0:00")
		expect(Juice.clock(3725)).toBe("62:05")
	end)
	test("comboStep: the highest step reached (Config.MiniGame.Combo shape)", function()
		expect({ Juice.comboStep(0, STEPS) }).toEqual({ 0, 1 })
		expect({ Juice.comboStep(2, STEPS) }).toEqual({ 0, 1 })
		expect({ Juice.comboStep(3, STEPS) }).toEqual({ 1, 1.2 })
		expect({ Juice.comboStep(9, STEPS) }).toEqual({ 2, 1.5 })
		expect({ Juice.comboStep(25, STEPS) }).toEqual({ 3, 2 })
	end)
	test("crossed: only going up into a new step", function()
		expect(Juice.crossed(2, 3, STEPS)).toBe(true)
		expect(Juice.crossed(3, 4, STEPS)).toBe(false)
		expect(Juice.crossed(5, 6, STEPS)).toBe(true)
		expect(Juice.crossed(0, 12, STEPS)).toBe(true)
		expect(Juice.crossed(4, 0, STEPS)).toBe(false)
		expect(Juice.crossed(10, 11, STEPS)).toBe(false)
	end)
	test("arc, breath, hop: end where they should", function()
		expect(Juice.arc(0, 50, 100, 0)).toBe(0)
		expect(Juice.arc(0, 50, 100, 1)).toBe(100)
		expect(Juice.arc(0, 100, 0, 0.5)).toBe(50)
		expect(Juice.arc(0, 50, 100, 2)).toBe(100)
		expect(near(Juice.breath(0, 2), 0, 1e-9)).toBeTruthy()
		expect(near(Juice.breath(1, 2), 1, 1e-9)).toBeTruthy()
		expect(Juice.breath(1, 0)).toBe(0)
		expect(Juice.hop(0, 2.6, 0.4)).toBe(0)
		expect(near(Juice.hop(0.2, 2.6, 0.4), 1, 1e-9)).toBeTruthy()
		expect(Juice.hop(1, 2.6, 0.4)).toBe(0)
		expect(near(Juice.hop(2.8, 2.6, 0.4), 1, 1e-9)).toBeTruthy()
		expect(Juice.hop(-1, 2.6, 0.4)).toBe(0)
	end)
	test("toastSeconds: base, longer for long text, capped", function()
		expect(Juice.toastSeconds("Hi", 2.6, 0.03, 5)).toBe(2.6)
		expect(near(Juice.toastSeconds(string.rep("a", 50), 2.6, 0.03, 5), 3.2, 1e-9)).toBeTruthy()
		expect(Juice.toastSeconds(string.rep("a", 500), 2.6, 0.03, 5)).toBe(5)
	end)
end)

T.describe("Celebrate words", function()
	local data = {
		Nurses = Nurses,
		Rarities = Rarities,
		Levels = Levels,
		Decor = { HeartLamp = { Name = "Heart Lamp", Icon = "💡" } },
		Rooms = { BathRoom = { Name = "Bath Room", Icon = "🛁" } },
	}
	test("LevelUp: the level's name and its unlock chips", function()
		local words = Words.of({ Kind = "LevelUp", Title = "Level up!", Icon = "🏥", Level = 3 }, data)
		expect(words.Sub).toBe("Lv 3 · " .. Levels[3].Name)
		expect(#words.Chips).toBe(math.min(4, #Levels[3].Unlocks))
		expect(words.Chips[1]).toBe(Levels[3].Unlocks[1])
		expect(words.Sound).toBe("LevelUp")
	end)
	test("LevelUp: a junk level shows no chips", function()
		local words = Words.of({ Kind = "LevelUp", Title = "Level up!", Icon = "🏥", Level = 99 }, data)
		expect(#words.Chips).toBe(0)
		expect(words.Sub).toBe("")
		words = Words.of({ Kind = "LevelUp", Title = "Level up!", Icon = "🏥", Level = 2.5 }, data)
		expect(#words.Chips).toBe(0)
	end)
	test("NewNurse: name, rarity and role chips", function()
		local id = Nurses.Order[1]
		local nurse = Nurses[id]
		local words = Words.of({ Kind = "NewNurse", Title = "New nurse!", Icon = "👩‍⚕️", NurseId = id }, data)
		expect(words.NurseId).toBe(id)
		expect(words.Rarity).toBe(nurse.Rarity)
		expect(words.Sub).toBe(nurse.Name)
		expect(words.Chips[1]).toBe(Rarities[nurse.Rarity].Icon .. " " .. nurse.Rarity)
		expect(words.Sound).toBe("Celebrate")
	end)
	test("NewNurse: role icons match the belt and the Journal (never an item's icon)", function()
		local source = fs.readFile(root .. "/src/client/UI/BeltView.luau")
		for role, icon in Words.ROLE_ICONS do
			local belt = string.match(source, "Pure%.ROLE_ICONS = {[^}]*" .. role .. ' = "([^"]+)"')
			expect(belt).toBe(icon)
		end
		for _, id in Nurses.Order do
			local nurse = Nurses[id]
			local words =
				Words.of({ Kind = "NewNurse", Title = "New nurse!", Icon = "👩‍⚕️", NurseId = id }, data)
			expect(words.Chips[2]).toBe(Words.ROLE_ICONS[nurse.Role] .. " " .. nurse.Role)
		end
	end)
	test("NewNurse: an unknown id (or Order) still celebrates, without a portrait", function()
		local words =
			Words.of({ Kind = "NewNurse", Title = "New nurse!", Icon = "👩‍⚕️", NurseId = "Order" }, data)
		expect(words.NurseId).toBeNil()
		expect(words.Title).toBe("New nurse!")
	end)
	test("JournalSet: the reward's cash and decor", function()
		local words = Words.of({
			Kind = "JournalSet",
			Title = "Set complete!",
			Icon = "📔",
			Rarity = "Rare",
			Cash = 1000,
			Decor = "HeartLamp",
		}, data)
		expect(words.Rarity).toBe("Rare")
		expect(words.Cash).toBe(1000)
		expect(words.Chips).toEqual({ "💰 1,000", "💡 Heart Lamp" })
	end)
	test("Room: its name from the extra Room field", function()
		local words = Words.of({ Kind = "Room", Title = "New room!", Icon = "🛁", Room = "BathRoom" }, data)
		expect(words.Sub).toBe("Bath Room")
		expect(words.Sound).toBe("Fanfare")
		words = Words.of({ Kind = "Room", Title = "New room!", Icon = "🛁", Room = "Order" }, data)
		expect(words.Sub).toBe("")
	end)
	test("junk is refused; long titles are cut to 3 words", function()
		expect(Words.of(nil, data)).toBeNil()
		expect(Words.of({ Kind = "Nope", Title = "x", Icon = "y" }, data)).toBeNil()
		expect(Words.of({ Kind = "Room", Title = 5, Icon = "y" }, data)).toBeNil()
		expect(Words.of({ Kind = "Room", Title = "one two three four", Icon = "🛁" }, data).Title).toBe(
			"one two three"
		)
	end)
	test("commas", function()
		expect(Words.commas(0)).toBe("0")
		expect(Words.commas(1000)).toBe("1,000")
		expect(Words.commas(1234567)).toBe("1,234,567")
	end)
end)
