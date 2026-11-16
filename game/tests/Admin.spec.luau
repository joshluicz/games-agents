--!strict
-- The admin panel's rules (Logic/Admin; game/README.md "Admin panel"): who is an admin, which actions and arguments
-- the Admin remote takes, and when the whole-server actions are allowed.

local T = require("./expect")
local expect, test = T.expect, T.test

local Admin = require("../src/shared/Logic/Admin")
local Patients = require("../src/shared/Data/Patients")
local Boosts = require("../src/shared/Data/Boosts")
local Nurses = require("../src/shared/Data/Nurses")

local OWNER = 2228783124
local FRIEND = 111
local STRANGER = 222

local function who(overrides: { [string]: any }?): Admin.Who
	local base: { [string]: any } = {
		Studio = false,
		CreatorIsUser = true,
		CreatorId = OWNER,
		UserIds = {},
		Resolved = {},
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base :: any
end

T.describe("Admin.isAdmin", function()
	test("the game's owner is an admin when a user owns the game", function()
		expect(Admin.isAdmin(OWNER, who())).toBe(true)
	end)

	test("a group-owned game's CreatorId is not a user", function()
		expect(Admin.isAdmin(OWNER, who({ CreatorIsUser = false }))).toBe(false)
	end)

	test("a hard-coded UserId is an admin", function()
		expect(Admin.isAdmin(FRIEND, who({ UserIds = { FRIEND } }))).toBe(true)
	end)

	test("a username the server looked up is an admin", function()
		expect(Admin.isAdmin(FRIEND, who({ Resolved = { [FRIEND] = true } }))).toBe(true)
	end)

	test("anyone else is not", function()
		expect(Admin.isAdmin(STRANGER, who({ UserIds = { FRIEND }, Resolved = { [FRIEND] = true } }))).toBe(false)
	end)

	test("in Studio anyone playing is, even a test player's negative id", function()
		expect(Admin.isAdmin(STRANGER, who({ Studio = true }))).toBe(true)
		expect(Admin.isAdmin(-1, who({ Studio = true }))).toBe(true)
	end)

	test("junk ids and a missing creator never match", function()
		expect(Admin.isAdmin(0, who({ CreatorId = 0 }))).toBe(false)
		expect(Admin.isAdmin(-1, who({ CreatorId = -1 }))).toBe(false)
		expect(Admin.isAdmin(0 / 0, who())).toBe(false)
		expect(Admin.isAdmin("2228783124", who())).toBe(false)
		expect(Admin.isAdmin(OWNER + 0.5, who())).toBe(false)
		expect(Admin.isAdmin(OWNER, nil :: any)).toBe(false)
	end)
end)

T.describe("Admin.valid", function()
	test("actions without an argument take nil only", function()
		for _, action in
			{
				"UnlockRooms",
				"AllDecor",
				"FinishTutorial",
				"RestartTutorial",
				"ResetDaily",
				"CompleteBook",
				"StoriesDue",
				"SkipToNight",
				"SkipToDay",
				"ToggleWinter",
				"AddPlayToday",
				"AddPlayTotal",
				"AddCureStat",
				"MaxBadges",
			}
		do
			expect(Admin.valid(action, nil, Patients)).toBe(true)
			expect(Admin.valid(action, 1, Patients)).toBe(false)
			expect(Admin.valid(action, "x", Patients)).toBe(false)
			expect(Admin.valid(action, {}, Patients)).toBe(false)
		end
	end)

	test("cash takes exactly 1,000 or 10,000", function()
		expect(Admin.valid("AddCash", 1000, Patients)).toBe(true)
		expect(Admin.valid("AddCash", 10000, Patients)).toBe(true)
		for _, junk in { 999, 1e15, -1000, 0 / 0, math.huge, "1000", nil } do
			expect(Admin.valid("AddCash", junk, Patients)).toBe(false)
		end
	end)

	test("stars take exactly 10 or 100", function()
		expect(Admin.valid("AddStars", 10, Patients)).toBe(true)
		expect(Admin.valid("AddStars", 100, Patients)).toBe(true)
		for _, junk in { 1000, 11, -10, 0 / 0, "10", nil } do
			expect(Admin.valid("AddStars", junk, Patients)).toBe(false)
		end
	end)

	test("spawning takes a Data/Patients id only", function()
		for _, patientId in Patients.Order do
			expect(Admin.valid("SpawnPatient", patientId, Patients)).toBe(true)
		end
		expect(Admin.valid("SpawnPatient", "Order", Patients)).toBe(false)
		expect(Admin.valid("SpawnPatient", "ShySprout", Patients)).toBe(false) -- a regular: Story sends those
		expect(Admin.valid("SpawnPatient", "", Patients)).toBe(false)
		expect(Admin.valid("SpawnPatient", string.rep("A", 500), Patients)).toBe(false)
		expect(Admin.valid("SpawnPatient", nil, Patients)).toBe(false)
		expect(Admin.valid("SpawnPatient", 5, Patients)).toBe(false)
	end)

	test("a boost takes a Data/Boosts id only", function()
		for _, boostId in Boosts.Order do
			expect(Admin.valid("AddBoost", boostId, Patients, Boosts)).toBe(true)
		end
		expect(Admin.valid("AddBoost", "Order", Patients, Boosts)).toBe(false)
		expect(Admin.valid("AddBoost", "Robux", Patients, Boosts)).toBe(false)
		expect(Admin.valid("AddBoost", nil, Patients, Boosts)).toBe(false)
		expect(Admin.valid("AddBoost", 3, Patients, Boosts)).toBe(false)
		expect(Admin.valid("AddBoost", "StarRush", Patients)).toBe(false) -- no boosts map: nothing is valid
	end)

	test("unknown or junk actions are refused", function()
		for _, junk in { "GiveRobux", "", "__index", "addcash", 5, nil, {} } do
			expect(Admin.valid(junk, nil, Patients)).toBe(false)
		end
	end)
end)

T.describe("Admin server-wide actions", function()
	test("are night, day, winter and the Agency's restock only", function()
		expect(Admin.serverWide("SkipToNight")).toBe(true)
		expect(Admin.serverWide("SkipToDay")).toBe(true)
		expect(Admin.serverWide("ToggleWinter")).toBe(true)
		expect(Admin.serverWide("RefillAgency")).toBe(true)
		expect(Admin.serverWide("Rebirth")).toBe(false)
		expect(Admin.serverWide("SpawnAmbulance")).toBe(false)
		expect(Admin.serverWide("AddCash")).toBe(false)
		expect(Admin.serverWide("SpawnPatient")).toBe(false)
		expect(Admin.serverWide("Nope")).toBe(false)
	end)

	test("need the admin alone in the server, or Studio", function()
		expect(Admin.serverWideAllowed(false, 1)).toBe(true)
		expect(Admin.serverWideAllowed(false, 2)).toBe(false)
		expect(Admin.serverWideAllowed(true, 6)).toBe(true)
	end)

	test("every action says what argument it takes", function()
		local kinds = { None = true, Cash = true, Stars = true, PatientId = true, BoostId = true, NurseId = true }
		for _, found in Admin.ACTIONS do
			expect(kinds[found.Arg]).toBe(true)
		end
	end)
end)

T.describe("Admin Progression v2 actions (build plan §B8)", function()
	test("the eight new actions exist with the right arguments", function()
		for action, arg in
			{
				Rebirth = "None",
				AddTreePoints = "None",
				RefillAgency = "None",
				NurseLevels = "None",
				GiveNurse = "NurseId",
				ChargeAbilities = "None",
				SpawnAmbulance = "None",
				SpawnHelicopter = "None",
			}
		do
			local found = Admin.ACTIONS[action]
			assert(found, "missing " .. action)
			expect(found.Arg).toBe(arg)
		end
	end)

	test("GiveNurse takes a Data/Nurses id only", function()
		expect(Admin.valid("GiveNurse", "PuffPup", Patients, Boosts, Nurses)).toBe(true)
		expect(Admin.valid("GiveNurse", "FounderFennec", Patients, Boosts, Nurses)).toBe(true)
		expect(Admin.valid("GiveNurse", "Order", Patients, Boosts, Nurses)).toBe(false)
		expect(Admin.valid("GiveNurse", "Nope", Patients, Boosts, Nurses)).toBe(false)
		expect(Admin.valid("GiveNurse", nil, Patients, Boosts, Nurses)).toBe(false)
		expect(Admin.valid("GiveNurse", 5, Patients, Boosts, Nurses)).toBe(false)
		expect(Admin.valid("GiveNurse", "PuffPup", Patients, Boosts)).toBe(false) -- no nurse map: nothing passes
		expect(Admin.valid("Rebirth", nil, Patients, Boosts, Nurses)).toBe(true)
		expect(Admin.valid("Rebirth", 1, Patients, Boosts, Nurses)).toBe(false)
		expect(Admin.valid("SpawnHelicopter", nil, Patients, Boosts, Nurses)).toBe(true)
	end)
end)
