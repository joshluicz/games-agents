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

------------------------------------------------------------------------------------------------------------------
-- Progression v2 (build plan §C T8): rings, holds, the new celebrations, cues, holds at stations, the Book's gates,
-- the cure bonus pops and Feel/HospitalFX's rules. Each block is loaded straight from the shipped source.
------------------------------------------------------------------------------------------------------------------

local Config = require("./config")
local Perks = dataModule("Perks")
local Themes = dataModule("Themes")
local Abilities = dataModule("Abilities")
local Wings = dataModule("Wings")
local Variants = dataModule("Variants")
local RebirthLogic = luau.load(fs.readFile(root .. "/src/shared/Logic/Rebirth.luau"), { debugName = "Logic.Rebirth" })()
local Hold = block("src/client/UI/Guide.luau", "-- BEGIN HOLD", "-- END HOLD", "Hold")
local Gate = block("src/client/UI/BookPanel.luau", "-- BEGIN GATE", "-- END GATE", "Gate")
local Bonus = block("src/client/Feel/CureFX.luau", "-- BEGIN BONUS", "-- END BONUS", "Bonus")
local FX = block("src/client/Feel/HospitalFX.luau", "-- BEGIN PURE", "-- END PURE", "Pure")

local function countWords(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

T.describe("Juice: rings and holds (Progression v2)", function()
	test("ringFraction: ready once readyAt has passed (or there is none)", function()
		expect(Juice.ringFraction(100, 60, 100)).toBe(1)
		expect(Juice.ringFraction(90, 60, 100)).toBe(1)
		expect(Juice.ringFraction(nil, 60, 100)).toBe(1)
		expect(Juice.ringFraction("soon", 60, 100)).toBe(1)
		expect(Juice.ringFraction(0 / 0, 60, 100)).toBe(1)
	end)
	test("ringFraction: the share of the cooldown already waited", function()
		expect(Juice.ringFraction(160, 60, 100)).toBe(0) -- just fired
		expect(Juice.ringFraction(130, 60, 100)).toBe(0.5)
		expect(near(Juice.ringFraction(115, 60, 100), 0.75, 1e-9)).toBeTruthy()
		expect(Juice.ringFraction(1000, 60, 100)).toBe(0) -- clock skew: never below empty
	end)
	test("ringFraction: a future readyAt with no usable cooldown is empty, never falsely ready", function()
		expect(Juice.ringFraction(130, nil, 100)).toBe(0)
		expect(Juice.ringFraction(130, 0, 100)).toBe(0)
		expect(Juice.ringFraction(130, -5, 100)).toBe(0)
		expect(Juice.ringFraction(130, math.huge, 100)).toBe(0)
	end)
	test("ringBeads: lit beads and the next one's share", function()
		expect({ Juice.ringBeads(0, 12) }).toEqual({ 0, 0 })
		expect({ Juice.ringBeads(0.5, 12) }).toEqual({ 6, 0 })
		local lit, partial = Juice.ringBeads(0.54, 12)
		expect(lit).toBe(6)
		expect(near(partial, 0.48, 1e-9)).toBeTruthy()
		expect({ Juice.ringBeads(1, 12) }).toEqual({ 12, 0 })
		expect({ Juice.ringBeads(7, 12) }).toEqual({ 12, 0 })
		expect({ Juice.ringBeads(-1, 12) }).toEqual({ 0, 0 })
		expect({ Juice.ringBeads(0 / 0, 12) }).toEqual({ 0, 0 })
		expect({ Juice.ringBeads(0.5, 0) }).toEqual({ 0, 0.5 }) -- at least one bead
	end)
	test("ringBeads: a ring only ever fills up as the cooldown passes", function()
		local last = -1
		for t = 0, 60 do
			local lit = Juice.ringBeads(Juice.ringFraction(160, 60, 100 + t), 12)
			expect(lit >= last).toBeTruthy()
			last = lit
		end
		expect(last).toBe(12)
	end)
	test("holdFill: smooth, or by quarters with reduced motion", function()
		expect(Juice.holdFill(0, 1.5)).toBe(0)
		expect(Juice.holdFill(0.75, 1.5)).toBe(0.5)
		expect(Juice.holdFill(9, 1.5)).toBe(1)
		expect(Juice.holdFill(-1, 1.5)).toBe(0)
		expect(Juice.holdFill(0.7, 1.5, 4)).toBe(0.25)
		expect(Juice.holdFill(0.75, 1.5, 4)).toBe(0.5)
		expect(Juice.holdFill(1.5, 1.5, 4)).toBe(1)
		expect(Juice.holdFill(0.5, 0)).toBe(0.5) -- a junk length holds for 1 s
	end)
end)

T.describe("Celebrate words (Progression v2)", function()
	local data = {
		Nurses = Nurses,
		Rarities = Rarities,
		Levels = Levels,
		Decor = {},
		Rooms = {},
		Perks = Perks,
		Themes = Themes,
		Abilities = Abilities,
		Unlocks = RebirthLogic.UNLOCKS,
		Config = Config,
	}
	local oddsChip = "🎲 1 in " .. math.floor(1 / Config.GoldenChance + 0.5)
	local function rebirth(count: any, theme: string?): any
		return Words.of({ Kind = "Rebirth", Title = "New branch!", Icon = "🏢", Count = count, Theme = theme }, data)
	end
	test("decimal: multipliers as kids read them", function()
		expect(Words.decimal(1.25)).toBe("1.25")
		expect(Words.decimal(1.5)).toBe("1.5")
		expect(Words.decimal(2)).toBe("2")
		expect(Words.decimal(3.75)).toBe("3.75")
	end)
	test("Rebirth: the count, the theme's look and colours, what it gave, then a card to pick", function()
		local words = rebirth(1, "Arctic")
		expect(words.Sticker).toBe("🏢 1")
		expect(words.Sub).toBe(Themes.Arctic.Icon .. " " .. Themes.Arctic.Name)
		expect(words.Colors).toEqual({ Themes.Arctic.Wall, Themes.Arctic.Roof, Themes.Arctic.Trim })
		expect(words.Chips[1]).toBe("×" .. Words.decimal(RebirthLogic.multiplier(1, Config)) .. " cash and stars")
		expect(words.Chips[2]).toBe("🌳 +" .. Config.Rebirth.PointsPerRebirth)
		expect(words.Chips[3]).toBe("👩‍⚕️ +1 nurse slot")
		expect(words.Points).toBe(Config.Rebirth.PointsPerRebirth)
		expect(words.Action).toBe("Perks")
		expect(words.Sound).toBe("Rebirth")
		expect(words.MaxChips).toBe(Words.REBIRTH_CHIPS)
	end)
	test("Rebirth: the multiplier matches Logic/Rebirth at every count; the slot stops at the roster max", function()
		for count = 1, 12 do
			local words = rebirth(count)
			expect(words.Chips[1]).toBe(
				"×" .. Words.decimal(RebirthLogic.multiplier(count, Config)) .. " cash and stars"
			)
			local roster = Config.Roster
			local grows = math.min(roster.Base + roster.PerRebirth * count, roster.Max)
				> math.min(roster.Base + roster.PerRebirth * (count - 1), roster.Max)
			expect(table.find(words.Chips, "👩‍⚕️ +1 nurse slot") ~= nil).toBe(grows)
		end
	end)
	test("Rebirth: Candy (no colours) and junk counts keep the usual look", function()
		local words = rebirth("x", "Candy")
		expect(words.Colors).toBeNil()
		expect(words.Sticker).toBeNil()
		expect(#words.Chips).toBe(0)
		expect(words.Action).toBe("Perks") -- every rebirth offers a card (the 🌳 fallback when all are owned)
		expect(rebirth(2, "Order").Sub).toBe("")
	end)
	test("Unlock: on its own, with Golden's odds shown (red line 3)", function()
		local words = Words.of({ Kind = "Unlock", Title = "New unlock!", Icon = "🌟", Unlock = "Golden" }, data)
		expect(words.Chips[1]).toBe("🌟 Golden patients")
		expect(words.Chips[2]).toBe(oddsChip)
		expect(words.Sub).toBe("Golden patients")
		words = Words.of({ Kind = "Unlock", Title = "New unlock!", Icon = "🌟", Unlock = "Nope" }, data)
		expect(#words.Chips).toBe(0)
	end)
	test("fold: unlocks join the Rebirth they came with, up to its chip limit", function()
		local words = rebirth(3, "Space")
		local before = #words.Chips
		for _, unlockId in RebirthLogic.unlocks(3) do
			expect(Words.fold(words, unlockId, data)).toBe(true)
		end
		expect(#words.Chips <= Words.REBIRTH_CHIPS).toBeTruthy()
		expect(#words.Chips > before).toBeTruthy()
		expect(table.find(words.Chips, oddsChip) ~= nil).toBeTruthy()
		expect(Words.fold(words, "Nope", data)).toBe(false)
		local nurse = Words.of(
			{ Kind = "NewNurse", Title = "New nurse!", Icon = "👩‍⚕️", NurseId = Nurses.Order[1] },
			data
		)
		expect(Words.fold(nurse, "Golden", data)).toBe(false)
	end)
	test("Perk: the card's name and words; the 🌳 fallback too", function()
		local id = Perks.Order[1]
		local words = Words.of({ Kind = "Perk", Title = "New perk!", Icon = Perks[id].Icon, Perk = id }, data)
		expect(words.Sub).toBe(Perks[id].Name)
		expect(words.Chips[1]).toBe(Perks[id].Icon .. " " .. Perks[id].Text)
		expect(words.Sound).toBe("Perk")
		words = Words.of({ Kind = "Perk", Title = "New perk!", Icon = "🌳", Perk = Perks.FallbackId }, data)
		expect(words.Chips[1]).toBe(Perks.Fallback.Icon .. " " .. Perks.Fallback.Text)
		words = Words.of({ Kind = "Perk", Title = "New perk!", Icon = "🃏", Perk = "Order" }, data)
		expect(#words.Chips).toBe(0)
	end)
	test("NurseLevel: the face, the level, and its trick getting stronger", function()
		local id = Nurses.Order[1]
		local nurse = Nurses[id]
		local ability = Abilities[nurse.Ability]
		local info =
			{ Kind = "NurseLevel", Title = "Level up!", Icon = "⬆️", NurseId = id, Level = 5, Ability = true }
		local words = Words.of(info, data)
		expect(words.NurseId).toBe(id)
		expect(words.Rarity).toBe(nurse.Rarity)
		expect(words.Sticker).toBe("⬆️ 5")
		expect(words.Chips[1]).toBe("⬆️ Lv 5")
		expect(words.Chips[2]).toBe(ability.Icon .. " " .. ability.Name)
		expect(words.Sound).toBe("LevelNurse")
		words = Words.of({ Kind = "NurseLevel", Title = "Level up!", Icon = "⬆️", NurseId = id, Level = 4 }, data)
		expect(#words.Chips).toBe(1)
	end)
	test("NurseLevel: a once-a-day trick never says it comes sooner", function()
		for _, id in Nurses.Order do
			local info =
				{ Kind = "NurseLevel", Title = "Level up!", Icon = "⬆️", NurseId = id, Level = 10, Ability = true }
			local sooner = table.find(Words.of(info, data).Chips, "🔁 Ready sooner") ~= nil
			expect(sooner).toBe(Abilities[Nurses[id].Ability].Daily ~= true)
		end
	end)
	test("NewNurse: its trick joins the chips", function()
		local id = Nurses.Order[1]
		local words = Words.of({ Kind = "NewNurse", Title = "New nurse!", Icon = "👩‍⚕️", NurseId = id }, data)
		local ability = Abilities[Nurses[id].Ability]
		expect(words.Chips[3]).toBe(ability.Icon .. " " .. ability.Name)
	end)
	test("every chip and sub-line stays short (≤ 6 words), every title ≤ 3", function()
		local infos = {}
		for count = 1, 10 do
			table.insert(
				infos,
				{ Kind = "Rebirth", Title = "New branch!", Icon = "🏢", Count = count, Theme = "Royal" }
			)
		end
		for _, id in Perks.Order do
			table.insert(infos, { Kind = "Perk", Title = "New perk!", Icon = "🃏", Perk = id })
		end
		for id in RebirthLogic.UNLOCKS do
			table.insert(infos, { Kind = "Unlock", Title = "New unlock!", Icon = "🎁", Unlock = id })
		end
		for _, id in Nurses.Order do
			table.insert(
				infos,
				{ Kind = "NurseLevel", Title = "Level up!", Icon = "⬆️", NurseId = id, Level = 10, Ability = true }
			)
		end
		for _, info in infos do
			local w = Words.of(info, data)
			expect(countWords(w.Title) <= 3).toBeTruthy()
			expect(countWords(w.Sub) <= 6).toBeTruthy()
			for _, chip in w.Chips do
				expect(countWords(chip) <= 6).toBeTruthy()
			end
		end
	end)
end)

T.describe("Sounds (Progression v2 cues)", function()
	local source = fs.readFile(root .. "/src/client/Feel/Sounds.luau")
	local first = string.find(source, "Sounds.CUES = table.freeze({", 1, true)
	local last = string.find(source, "} :: { [string]: Cue })", 1, true)
	local cues = if first and last then string.sub(source, first, last) else ""
	local V2 = {
		"Rebirth",
		"Perk",
		"Node",
		"Ability",
		"Siren",
		"Heli",
		"Ding",
		"Sold",
		"Bought",
		"Restock",
		"Triage",
		"Splash",
		"Brew",
		"LevelNurse",
	}
	test("every cue the build plan lists (§B9) is in Sounds.CUES and Sounds.V2_CUES", function()
		expect(cues ~= "").toBeTruthy()
		for _, name in V2 do
			expect(string.find(cues, "\n\t" .. name .. " = {", 1, true) ~= nil).toBeTruthy()
			expect(string.find(source, '\t"' .. name .. '",', 1, true) ~= nil).toBeTruthy()
		end
	end)
	test("the Celebrate sounds exist too", function()
		for _, name in Words.KINDS do
			expect(string.find(cues, "\n\t" .. name .. " = {", 1, true) ~= nil).toBeTruthy()
		end
	end)
	test("only built-in rbxasset sounds (red line 2)", function()
		for id in string.gmatch(source, '"(rbxasset[^"]*)"') do
			expect(string.sub(id, 1, 18)).toBe("rbxasset://sounds/")
		end
		expect(string.find(source, "rbxassetid://", 1, true)).toBeNil()
	end)
end)

T.describe("Guide: station holds follow the plot (Progression v2)", function()
	test("teamMake: the team factors, junk skipped", function()
		expect(Hold.teamMake("Bath=0.8,Cocoa=0.6")).toEqual({ Bath = 0.8, Cocoa = 0.6 })
		expect(Hold.teamMake("")).toEqual({})
		expect(Hold.teamMake(nil)).toEqual({})
		expect(Hold.teamMake("Bath=2,Potion=0,Plaster=x,=0.5,Cocoa=0.9")).toEqual({ Cocoa = 0.9 })
	end)
	test("seconds: team, then a rush while it runs, never below the floor or above the base", function()
		local team = { Bath = 0.8 }
		expect(Hold.seconds(2, "Bath", team, nil, nil, 100, 0.3)).toBe(1.6)
		expect(Hold.seconds(2, "Potion", team, nil, nil, 100, 0.3)).toBe(2)
		expect(Hold.seconds(2, "Bath", team, 110, 0.5, 100, 0.3)).toBe(0.8) -- Busy Paws
		expect(Hold.seconds(2, "Bath", team, 90, 0.5, 100, 0.3)).toBe(1.6) -- the rush is over
		expect(Hold.seconds(2, "Potion", team, 110, 0, 100, 0.3)).toBe(0.3) -- Time Bubble: the shortest hold
		expect(Hold.seconds(0.4, "Potion", {}, 110, 0.5, 100, 0.3)).toBe(0.3)
		expect(Hold.seconds(2, "Potion", {}, 110, 3, 100, 0.3)).toBe(2) -- a junk factor never slows it
		expect(Hold.seconds(2, nil, team, nil, nil, 100, 0.3)).toBe(2)
	end)
end)

T.describe("BookPanel: rebirth wings and the Golden sticker (Progression v2)", function()
	test("gates are words: the branch count, and 'by air' for the air-only wing; no emoji, no lock", function()
		expect(Gate.wingWords(Wings.Starter, 0)).toBe("")
		expect(Gate.wingWords(Wings.Sunny, 0)).toBe("From branch 1")
		expect(Gate.wingWords(Wings.Sunny, 1)).toBe("")
		expect(Gate.wingWords(Wings.Sky, 1)).toBe("From branch 2 · by air")
		expect(Gate.wingWords(Wings.Sky, 2)).toBe("By air only")
		expect(Gate.wingWords(Wings.Sky, "x")).toBe("From branch 2 · by air")
		expect(Gate.wingWords(nil, 3)).toBe("")
		for _, id in Wings.Order do
			expect(string.find(Gate.wingWords(Wings[id], 0), "🔒", 1, true)).toBeNil() -- no lock icon
			expect(string.find(Gate.wingWords(Wings[id], 0), "🏢", 1, true)).toBeNil()
		end
	end)
	test("stickers: Golden first, then Data/Variants order", function()
		local text, golden = Gate.stickers({ Sparkly = true, Golden = true }, Variants)
		expect(text).toBe(Variants.Golden.Icon .. Variants.Sparkly.Icon)
		expect(golden).toBe(true)
		text, golden = Gate.stickers({ Frosty = true }, Variants)
		expect(text).toBe(Variants.Frosty.Icon)
		expect(golden).toBe(false)
		expect({ Gate.stickers(nil, Variants) }).toEqual({ "", false })
	end)
end)

T.describe("CureFX: bonus pops (Progression v2)", function()
	test(
		"Golden, 🚑 ×3 and +20% ↕️ from the payload (the hot tub's 🛁 line is gone), numbers from Config",
		function()
			local lines = Bonus.lines({ Variant = "Golden", Urgent = "AE", Escorted = true, Soaked = true }, {}, Config)
			local texts = {}
			for _, line in lines do
				table.insert(texts, line.Text)
			end
			expect(texts).toEqual({
				"🌟 Golden!",
				"🚑 ×" .. Config.AE.CashMultiplier,
				"+" .. math.floor(Config.Escort.CashBonus * 100 + 0.5) .. "% ↕️",
			})
			expect(texts[2]).toBe("🚑 ×3")
			expect(texts[3]).toBe("+20% ↕️")
			expect(texts[4]).toBeNil()
		end
	)
	test("the helicopter's VIP, and facts read off the patient when the payload has none", function()
		local lines = Bonus.lines({ Variant = "Sparkly" }, { Urgent = "VIP", Escorted = true }, Config)
		expect(lines[1].Text).toBe("🚁 ×" .. Config.VIP.CashMultiplier)
		expect(lines[2].Kind).toBe("Escort")
		-- the payload wins over the model
		lines = Bonus.lines({ Urgent = "", Escorted = false }, { Urgent = "AE", Escorted = true }, Config)
		expect(#lines).toBe(0)
	end)
	test("nothing for a plain cure or junk", function()
		expect(#Bonus.lines({ PatientId = "x" }, {}, Config)).toBe(0)
		expect(#Bonus.lines(nil, nil, Config)).toBe(0)
		expect(#Bonus.lines({ Urgent = "AE" }, nil, {})).toBe(0) -- no Config number, no line
	end)
end)

T.describe("HospitalFX rules (Progression v2)", function()
	test("fresh: only recent events play (late joiners see nothing)", function()
		expect(FX.fresh(100, 103, 6)).toBe(true)
		expect(FX.fresh(100, 107, 6)).toBe(false)
		expect(FX.fresh(100, 99.5, 6)).toBe(true) -- a little clock skew
		expect(FX.fresh(100, 95, 6)).toBe(false)
		expect(FX.fresh(0, 3, 6)).toBe(false) -- 0 = never
		expect(FX.fresh(nil, 3, 6)).toBe(false)
		expect(FX.fresh("x", 3, 6)).toBe(false)
	end)
	test("flash: the lights take turns; calm is slower and softer (no strobing)", function()
		local seenFast, seenCalm = {}, {}
		for step = 0, 19 do
			local on, bright = FX.flash(step * 0.1, false)
			seenFast[on] = true
			expect(bright).toBe(1)
		end
		local swaps = 0
		local last = FX.flash(0, true)
		for step = 1, 20 do
			local on, bright = FX.flash(step * 0.1, true)
			seenCalm[on] = true
			expect(bright < 1).toBeTruthy()
			if on ~= last then
				swaps += 1
			end
			last = on
		end
		expect(seenFast[1] and seenFast[2]).toBeTruthy()
		expect(seenCalm[1] and seenCalm[2]).toBeTruthy()
		expect(swaps <= 3).toBeTruthy()
		-- even the busy flash swaps at most 4 times a second (well under the 3 Hz photosensitivity line per light)
		local fastSwaps = 0
		local before = FX.flash(0, false)
		for step = 1, 100 do
			local on = FX.flash(step * 0.01, false)
			if on ~= before then
				fastSwaps += 1
			end
			before = on
		end
		expect(fastSwaps <= 4).toBeTruthy()
	end)
	test("heli: in, stay, out, done; a late look joins where the flight is", function()
		expect(FX.heli(0)).toBe("In")
		expect(select(2, FX.heli(1))).toBe(FX.HELI_IN - 1)
		expect(FX.heli(FX.HELI_IN + 0.1)).toBe("Stay")
		expect(FX.heli(FX.HELI_IN + FX.HELI_STAY + 0.1)).toBe("Out")
		expect(FX.heli(FX.HELI_IN + FX.HELI_STAY + FX.HELI_OUT)).toBe("Done")
		expect(FX.heli(-5)).toBe("In")
		expect(FX.heli(0 / 0)).toBe("In")
	end)
	test("grow-in: bottom first, the top last, each fading 0 -> 1", function()
		expect(FX.growDelay(0, 0, 20)).toBe(0)
		expect(FX.growDelay(20, 0, 20)).toBe(FX.GROW_SPREAD)
		expect(FX.growDelay(5, 5, 5)).toBe(0)
		expect(FX.growAlpha(0, 0)).toBe(0)
		expect(FX.growAlpha(0.5, 0.6)).toBe(0)
		expect(FX.growAlpha(FX.GROW_SECONDS, 0)).toBe(1)
		expect(FX.growAlpha(99, 0.3)).toBe(1)
		local last = 0
		for step = 0, 10 do
			local a = FX.growAlpha(step * FX.GROW_SECONDS / 10, 0)
			expect(a >= last).toBeTruthy()
			last = a
		end
	end)
	test("earshot: loud up close, softer away, silent past its reach", function()
		expect(FX.earshot(5, 50)).toBe(1)
		expect(FX.earshot(51, 50)).toBe(0)
		local mid = FX.earshot(30, 50)
		expect(mid > 0.25 and mid < 1).toBeTruthy()
		expect(FX.earshot(50, 50)).toBe(0.25)
		expect(FX.earshot(0 / 0, 50)).toBe(0)
		expect(FX.earshot(5, 0)).toBe(0)
	end)
end)
