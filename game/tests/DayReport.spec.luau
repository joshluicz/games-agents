--!nocheck
-- Server/DayReport, loaded WHOLE with stand-in services: the day's tally and what flush sends. The Cash line
-- (UI direction "What a Lv 1 player sees": patients treated, Cash, Stars) needs CashGained: the cash the player's
-- treatments paid that day, counted on the server from the number Cure hands to Economy.addCash. In memory only:
-- nothing here is saved, so no save can be broken, and a tally without the field reads as 0.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local World = require("./worldmock")

local PATH = "src/server/DayReport.luau"

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
		end,
		Fire = function(_, ...)
			for _, fn in handlers do
				fn(...)
			end
		end,
	}
end

-- A server with `names` as its players. rig.Sent[player] is the last report fired at them.
local function boot(names: { string })
	local rig = { Sent = {}, Saves = {}, Players = {}, Clock = 1000, Goal = { Kind = "None", Id = "", Icon = "" } }
	local players = { PlayerAdded = signal(), PlayerRemoving = signal() }
	function players:GetPlayers()
		return table.clone(rig.Players)
	end
	local function join(name: string)
		local player = { Name = name, Parent = players }
		function player:IsA(class)
			return class == "Player"
		end
		table.insert(rig.Players, player)
		rig.Saves[player] = { Tutorial = "Done" }
		rig[name] = player
		return player
	end
	for _, name in names do
		join(name)
	end
	local modules = {
		Remotes = {
			DayReport = {
				FireClient = function(_, player, report)
					rig.Sent[player] = report
				end,
			},
		},
		Types = {},
		Tutorial = {
			active = function(step)
				return step ~= "Done"
			end,
		},
		PlayerData = {
			get = function(player)
				return rig.Saves[player]
			end,
		},
		Progress = {
			nextGoal = function()
				return rig.Goal
			end,
		},
	}
	local env = {
		game = {
			GetService = function(_, name)
				if name == "Players" then
					return players
				end
				return { Shared = { Remotes = "Remotes", Types = "Types", Logic = { Tutorial = "Tutorial" } } }
			end,
		},
		script = { Parent = { PlayerData = "PlayerData", Progress = "Progress" } },
		require = function(name)
			return modules[name]
		end,
		typeof = function(value)
			return if type(value) == "table" and value.IsA then "Instance" else type(value)
		end,
		os = {
			clock = function()
				return rig.Clock
			end,
		},
	}
	local source = fs.readFile(World.find(PATH))
	rig.DayReport = luau.load(source, { debugName = PATH, environment = env, injectGlobals = true })()
	rig.DayReport.start()
	rig.Clock += 600 -- nobody is a newcomer any more
	return rig
end

T.describe("Server/DayReport: the day's tally (CashGained for the Cash line)", function()
	test("the helper's report carries the cash their treatments paid; stars and patients as before", function()
		local rig = boot({ "Ann" })
		local D, ann = rig.DayReport, rig.Ann
		D.record(ann, { PatientId = "ToastPup" }, true, 2, 30)
		D.record(ann, { PatientId = "ToastPup" }, true, 1, 45.9)
		D.record(ann, { PatientId = "DewDuck" }, false, 0, 25)
		D.flush()
		expect(rig.Sent[ann]).toEqual({
			Cured = 3,
			CashGained = 100,
			NewPages = { "ToastPup" },
			StarsGained = 3,
			Next = { Kind = "None", Id = "", Icon = "" },
		})
	end)

	test("each player's own cash: a friend who helps gets the cash, the owner gets the stars and no cash", function()
		local rig = boot({ "Owner", "Friend" })
		local D = rig.DayReport
		-- what Server/Cure does when a friend treats at the owner's clinic
		D.record(rig.Friend, { PatientId = "ToastPup" }, false, 0, 40)
		D.record(rig.Owner, { PatientId = "ToastPup" }, false, 2, 0)
		D.flush()
		expect(rig.Sent[rig.Friend].CashGained).toBe(40)
		expect(rig.Sent[rig.Friend].StarsGained).toBe(0)
		expect(rig.Sent[rig.Owner].CashGained).toBe(0)
		expect(rig.Sent[rig.Owner].StarsGained).toBe(2)
		expect(rig.Sent[rig.Owner].Cured).toBe(1)
	end)

	test("junk cash never counts: missing (an older caller), negative, NaN, infinite, not a number", function()
		local rig = boot({ "Ann" })
		local D, ann = rig.DayReport, rig.Ann
		D.record(ann, { PatientId = "ToastPup" }, false, 1)
		D.record(ann, { PatientId = "ToastPup" }, false, 1, -500)
		D.record(ann, { PatientId = "ToastPup" }, false, 1, 0 / 0)
		D.record(ann, { PatientId = "ToastPup" }, false, 1, math.huge)
		D.record(ann, { PatientId = "ToastPup" }, false, 1, "999")
		D.record(ann, nil, false, 1, 7)
		D.flush()
		expect(rig.Sent[ann].CashGained).toBe(7)
		expect(rig.Sent[ann].Cured).toBe(6)
	end)

	test("a new day starts at 0; a quiet day still reports, with Cash 0", function()
		local rig = boot({ "Ann" })
		local D, ann = rig.DayReport, rig.Ann
		D.record(ann, { PatientId = "ToastPup" }, false, 1, 60)
		D.flush()
		expect(rig.Sent[ann].CashGained).toBe(60)
		D.flush()
		expect(rig.Sent[ann].CashGained).toBe(0)
		expect(rig.Sent[ann].Cured).toBe(0)
	end)

	test("report(): a missing tally or a tally without the field reads as 0", function()
		local D = boot({}).DayReport
		local next = { Kind = "Room", Id = "BathRoom", Icon = "🛁" }
		expect(D.report(nil, next)).toEqual({ Cured = 0, CashGained = 0, NewPages = {}, StarsGained = 0, Next = next })
		local old = D.report({ Cured = 2, NewPages = { "DewDuck" }, StarsGained = 1 }, next)
		expect(old.CashGained).toBe(0)
		expect(old.Cured).toBe(2)
		expect(old.NewPages).toEqual({ "DewDuck" })
	end)

	test(
		"only players in the server are counted; the tutorial and a newcomer with nothing treated stay quiet",
		function()
			local rig = boot({ "Ann", "Tut" })
			local D = rig.DayReport
			D.record({ Name = "Ghost" }, { PatientId = "ToastPup" }, false, 1, 50) -- not a Player
			rig.Saves[rig.Tut].Tutorial = "Step2"
			D.record(rig.Tut, { PatientId = "ToastPup" }, false, 1, 50)
			D.flush()
			expect(rig.Sent[rig.Tut]).toBeNil()
			expect(rig.Sent[rig.Ann].CashGained).toBe(0)
		end
	)

	test(
		"the client never sends it: DayReport is fired by the server only, and Cure passes the cash it paid",
		function()
			local cure = fs.readFile(World.find("src/server/Cure.luau"))
			assert(string.find(cure, "DayReport.record, helper, cure, newPage, helperStars, reward.Cash)", 1, true))
			assert(string.find(cure, "DayReport.record, owner, cure, false, reward.Stars, 0)", 1, true))
			local source = fs.readFile(World.find(PATH))
			assert(not string.find(source, "OnServerEvent", 1, true), "DayReport listens to no client")
			assert(not string.find(source, "PlayerData.update", 1, true), "the tally is in memory: nothing is saved")
		end
	)
end)
