--!strict
-- Regulars' story rules (build plan §B6, Task 4). Pure: runs in Lune.
-- A story day is a UTC day number (os.time() // 86400). One beat per regular per day; beats wait for you.

local T = require("./expect")
local expect, test = T.expect, T.test

local Story = require("../src/shared/Logic/Story")
local Regulars = require("../src/shared/Data/Regulars")

local function fiveBeats(): { any }
	local beats = {}
	for index = 1, 5 do
		table.insert(beats, { Emote = "🙂", Bubble = "Beat " .. index })
	end
	return beats
end

T.describe("Story.unlocked", function()
	test("only ShySprout at 0 stars", function()
		expect(Story.unlocked(Regulars, 0)).toEqual({ "ShySprout" })
	end)

	test("GrumpyTeapot joins at exactly 40 stars", function()
		expect(Story.unlocked(Regulars, 39)).toEqual({ "ShySprout" })
		expect(Story.unlocked(Regulars, 40)).toEqual({ "ShySprout", "GrumpyTeapot" })
	end)

	test("all three at 120 stars, in Data order", function()
		expect(Story.unlocked(Regulars, 120)).toEqual({ "ShySprout", "GrumpyTeapot", "DizzyComet" })
		expect(Story.unlocked(Regulars, 9999)).toEqual({ "ShySprout", "GrumpyTeapot", "DizzyComet" })
	end)

	test("junk stars count as 0", function()
		expect(Story.unlocked(Regulars, (nil :: any) :: number)).toEqual({ "ShySprout" })
		expect(Story.unlocked(Regulars, 0 / 0)).toEqual({ "ShySprout" })
	end)
end)

T.describe("Story.due", function()
	test("a regular who never visited is due", function()
		expect(Story.due(nil, 100)).toBe(true)
	end)

	test("not again on the same day, but the next day", function()
		expect(Story.due({ Beat = 1, LastBeatDay = 100 }, 100)).toBe(false)
		expect(Story.due({ Beat = 1, LastBeatDay = 100 }, 101)).toBe(true)
	end)

	test("missed days skip nothing: still due after a long break", function()
		expect(Story.due({ Beat = 2, LastBeatDay = 100 }, 140)).toBe(true)
	end)

	test("a LastBeatDay in the future (another server's clock) is not due yet", function()
		expect(Story.due({ Beat = 1, LastBeatDay = 101 }, 100)).toBe(false)
	end)
end)

T.describe("Story.advance", function()
	test("the first visit makes Beat 1 today", function()
		expect(Story.advance(nil, 100)).toEqual({ Beat = 1, LastBeatDay = 100 })
	end)

	test("increments Beat and sets the day", function()
		expect(Story.advance({ Beat = 2, LastBeatDay = 90 }, 100)).toEqual({ Beat = 3, LastBeatDay = 100 })
	end)

	test("returns a new entry and leaves the old one alone", function()
		local entry = { Beat = 1, LastBeatDay = 50 }
		local nextEntry = Story.advance(entry, 51)
		expect(entry).toEqual({ Beat = 1, LastBeatDay = 50 })
		expect(nextEntry == entry).toBe(false)
	end)
end)

T.describe("Story.finished", function()
	test("not before the first visit", function()
		expect(Story.finished(nil, 5)).toBe(false)
	end)

	test("not at Beat 4 of 5", function()
		expect(Story.finished({ Beat = 4, LastBeatDay = 1 }, 5)).toBe(false)
	end)

	test("finished at Beat 5", function()
		expect(Story.finished({ Beat = 5, LastBeatDay = 1 }, 5)).toBe(true)
		expect(Story.finished({ Beat = 6, LastBeatDay = 1 }, 5)).toBe(true)
	end)

	test("accepts the Beats list as well as a count", function()
		expect(Story.finished({ Beat = 5, LastBeatDay = 1 }, Regulars.ShySprout.Beats)).toBe(true)
		expect(Story.finished({ Beat = 3, LastBeatDay = 1 }, Regulars.ShySprout.Beats)).toBe(false)
	end)
end)

T.describe("Story.beat", function()
	test("a first visit tells beat 1", function()
		expect(Story.beat(nil, 100, 5)).toBe(1)
	end)

	test("a due visit tells the next beat", function()
		expect(Story.beat({ Beat = 1, LastBeatDay = 99 }, 100, 5)).toBe(2)
	end)

	test("already advanced today: repeats today's beat", function()
		expect(Story.beat({ Beat = 1, LastBeatDay = 100 }, 100, 5)).toBe(1)
	end)

	test("a finished story stays on the last beat", function()
		expect(Story.beat({ Beat = 5, LastBeatDay = 90 }, 100, 5)).toBe(5)
	end)
end)

T.describe("Story.nextDue", function()
	test("a fresh clinic gets ShySprout first", function()
		expect(Story.nextDue(Regulars, {}, 0, 100, false)).toBe("ShySprout")
	end)

	test("nobody once ShySprout visited today and nobody else is unlocked", function()
		local story = { ShySprout = { Beat = 1, LastBeatDay = 100 } }
		expect(Story.nextDue(Regulars, story, 0, 100, false)).toBeNil()
	end)

	test("GrumpyTeapot comes once unlocked, in parallel with ShySprout", function()
		local story = { ShySprout = { Beat = 1, LastBeatDay = 100 } }
		expect(Story.nextDue(Regulars, story, 40, 100, false)).toBe("GrumpyTeapot")
	end)

	test("ShySprout is due again the next UTC day", function()
		local story = { ShySprout = { Beat = 1, LastBeatDay = 100 } }
		expect(Story.nextDue(Regulars, story, 0, 101, false)).toBe("ShySprout")
	end)

	test("a finished story never comes back", function()
		local story = { ShySprout = { Beat = 5, LastBeatDay = 90 } }
		expect(Story.nextDue(Regulars, story, 0, 100, false)).toBeNil()
	end)

	test("DizzyComet, the night regular, only comes at night", function()
		local story = {
			ShySprout = { Beat = 2, LastBeatDay = 100 },
			GrumpyTeapot = { Beat = 1, LastBeatDay = 100 },
		}
		expect(Story.nextDue(Regulars, story, 120, 100, false)).toBeNil()
		expect(Story.nextDue(Regulars, story, 120, 100, true)).toBe("DizzyComet")
	end)

	test("a nil story table is a fresh clinic", function()
		expect(Story.nextDue(Regulars, nil, 0, 100, false)).toBe("ShySprout")
	end)

	test(
		"a regular the clinic can't treat yet is not due (can): the next one is, and it is asked about each",
		function()
			-- nobody: everyone can come
			expect(Story.nextDue(Regulars, {}, 120, 100, true, function()
				return true
			end)).toBe("ShySprout")
			-- ShySprout can't be treated: GrumpyTeapot is named instead, never held back behind it
			local asked = {}
			local function notSprout(regularId)
				table.insert(asked, regularId)
				return regularId ~= "ShySprout"
			end
			expect(Story.nextDue(Regulars, {}, 120, 100, true, notSprout)).toBe("GrumpyTeapot")
			expect(asked[1]).toBe("ShySprout")
			expect(asked[2]).toBe("GrumpyTeapot")
			-- DizzyComet (a Lv 2 case) at a Lv 1 clinic, the others told today: nobody is due
			local story = {
				ShySprout = { Beat = 2, LastBeatDay = 100 },
				GrumpyTeapot = { Beat = 1, LastBeatDay = 100 },
			}
			expect(Story.nextDue(Regulars, story, 120, 100, true, function(regularId)
				return regularId ~= "DizzyComet"
			end)).toBeNil()
			-- only a true answer lets it come; it isn't asked about one who isn't due anyway
			asked = {}
			expect(Story.nextDue(Regulars, story, 120, 100, true, function(regularId)
				table.insert(asked, regularId)
				return nil
			end)).toBeNil()
			expect(#asked).toBe(1)
			expect(asked[1]).toBe("DizzyComet")
		end
	)
end)

T.describe("a whole story arc", function()
	test("five visits on five days finish it; extra cures on the same day do nothing", function()
		local beats = #Regulars.ShySprout.Beats
		local entry: Story.Entry? = nil
		local day = 200
		for visit = 1, beats do
			expect(Story.due(entry, day)).toBe(true)
			expect(Story.beat(entry, day, beats)).toBe(visit)
			entry = Story.advance(entry, day)
			-- A second cure the same UTC day is not due, so it can't advance.
			expect(Story.due(entry, day)).toBe(false)
			expect(Story.finished(entry, beats)).toBe(visit == beats)
			day += 1 + (visit % 3) -- days between visits vary; nothing is skipped
		end
		expect((entry :: Story.Entry).Beat).toBe(5)
	end)
end)

T.describe("Story.unrewarded", function()
	test("a finished story whose decor reward is missing", function()
		local story = { ShySprout = { Beat = 5, LastBeatDay = 9 } }
		expect(Story.unrewarded(Regulars, story, {}, {})).toEqual({ "ShySprout" })
	end)

	test("nothing once the reward is owned", function()
		local story = { ShySprout = { Beat = 5, LastBeatDay = 9 } }
		expect(Story.unrewarded(Regulars, story, { SproutMascot = true }, {})).toEqual({})
	end)

	test("nothing for an unfinished story", function()
		local story = { ShySprout = { Beat = 4, LastBeatDay = 9 } }
		expect(Story.unrewarded(Regulars, story, {}, {})).toEqual({})
	end)

	test("a room reward checks owned rooms", function()
		local regulars = {
			Order = { "Builder" },
			Builder = { UnlockStars = 0, Beats = fiveBeats(), Reward = "Ward", RewardKind = "Room" },
		}
		local story = { Builder = { Beat = 5, LastBeatDay = 9 } }
		expect(Story.unrewarded(regulars, story, {}, {})).toEqual({ "Builder" })
		expect(Story.unrewarded(regulars, story, { Ward = true }, {})).toEqual({ "Builder" })
		expect(Story.unrewarded(regulars, story, {}, { Ward = true })).toEqual({})
	end)
end)

T.describe("Story.nightOnly", function()
	test("only the Night wing's regulars are night-only", function()
		expect(Story.nightOnly(Regulars.DizzyComet)).toBe(true)
		expect(Story.nightOnly(Regulars.ShySprout)).toBe(false)
		expect(Story.nightOnly(Regulars.GrumpyTeapot)).toBe(false)
	end)
end)

T.describe("the Real Clinic keeps the stories", function()
	test("the same regulars, unlocks, rewards and five beats; only their case is new (design §11)", function()
		local rows = {}
		for _, id in Regulars.Order do
			local regular = Regulars[id]
			rows[id] = { regular.UnlockStars, regular.Reward, regular.RewardKind, #regular.Beats, regular.Wing }
		end
		expect(rows).toEqual({
			ShySprout = { 0, "SproutMascot", "Decor", 5, "Starter" },
			GrumpyTeapot = { 40, "LuckyKettle", "Decor", 5, "Starter" },
			DizzyComet = { 120, "CometLantern", "Decor", 5, "Night" },
		})
		-- a finished story is still finished, and its reward still due if it's missing
		local story = { GrumpyTeapot = { Beat = 5, LastBeatDay = 100 } }
		expect(Story.finished(story.GrumpyTeapot, Regulars.GrumpyTeapot.Beats)).toBe(true)
		expect(Story.unrewarded(Regulars, story, {}, {})).toEqual({ "GrumpyTeapot" })
	end)
end)
