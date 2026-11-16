--!strict
-- The admin panel's rules (Logic/Admin; game/README.md "Admin panel"): who is an admin, which actions and arguments
-- the Admin remote takes, and when the whole-server actions are allowed.

local T = require("./expect")
local expect, test = T.expect, T.test

local Admin = require("../src/shared/Logic/Admin")
local Patients = require("../src/shared/Data/Patients")

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

	test("unknown or junk actions are refused", function()
		for _, junk in { "GiveRobux", "", "__index", "addcash", 5, nil, {} } do
			expect(Admin.valid(junk, nil, Patients)).toBe(false)
		end
	end)
end)

T.describe("Admin server-wide actions", function()
	test("are night, day and winter only", function()
		expect(Admin.serverWide("SkipToNight")).toBe(true)
		expect(Admin.serverWide("SkipToDay")).toBe(true)
		expect(Admin.serverWide("ToggleWinter")).toBe(true)
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
		local kinds = { None = true, Cash = true, Stars = true, PatientId = true }
		for _, found in Admin.ACTIONS do
			expect(kinds[found.Arg]).toBe(true)
		end
	end)
end)
