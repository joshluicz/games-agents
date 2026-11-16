--!strict
-- Room unlock rules and the "next goal" (build plan §B6, Task 3).

local T = require("./expect")
local expect, test = T.expect, T.test

local Progress = require("../src/shared/Logic/Progress")
local Schema = require("../src/shared/Logic/Schema")
local Rooms = require("../src/shared/Data/Rooms")
local Upgrades = require("../src/shared/Data/Upgrades")

local function save(stars: number, cash: number, rooms: { string }?): Schema.Data
	local data = Schema.default()
	data.Stars = stars
	data.Cash = cash
	for _, roomId in rooms or {} do
		data.Rooms[roomId] = true
	end
	return data
end

local ALL_BUT_WINTER = { "BathRoom", "Ward", "Garden" }
local ALL_ROOMS = { "BathRoom", "Ward", "WinterWing", "Garden" }

T.describe("Progress.canBuyRoom", function()
	test("needs the stars first: Need ⭐10 at 5 stars", function()
		local ok, message = Progress.canBuyRoom(save(5, 1000), Rooms.BathRoom, "BathRoom")
		expect(ok).toBe(false)
		expect(message).toBe("Need ⭐10")
	end)

	test("is false when the room is already owned", function()
		local ok, message = Progress.canBuyRoom(save(99, 9999, { "BathRoom" }), Rooms.BathRoom, "BathRoom")
		expect(ok).toBe(false)
		expect(message).toBe("Already yours!")
		expect((Progress.canBuyRoom(save(99, 9999), Rooms.Stand, "Stand"))).toBe(false)
	end)

	test("is true when stars and cash are enough", function()
		local ok = Progress.canBuyRoom(save(10, 150), Rooms.BathRoom, "BathRoom")
		expect(ok).toBe(true)
	end)

	test("needs the cash once the stars are there", function()
		local ok, message = Progress.canBuyRoom(save(10, 149), Rooms.BathRoom, "BathRoom")
		expect(ok).toBe(false)
		expect(message).toBe("Need 💰150")
	end)

	test("a winter room is only for sale in winter", function()
		local data = save(40, 500)
		local ok, message = Progress.canBuyRoom(data, Rooms.WinterWing, "WinterWing", false)
		expect(ok).toBe(false)
		expect(message).toBe("❄️ Winter only!")
		expect((Progress.canBuyRoom(data, Rooms.WinterWing, "WinterWing"))).toBe(false)
		expect((Progress.canBuyRoom(data, Rooms.WinterWing, "WinterWing", true))).toBe(true)
	end)

	test("in winter, a winter room still needs its stars", function()
		local ok, message = Progress.canBuyRoom(save(39, 500), Rooms.WinterWing, "WinterWing", true)
		expect(ok).toBe(false)
		expect(message).toBe("Need ⭐40")
	end)

	test("never errors on junk", function()
		expect((Progress.canBuyRoom(nil, Rooms.BathRoom, "BathRoom"))).toBe(false)
		expect((Progress.canBuyRoom(save(99, 9999), nil, "Nope"))).toBe(false)
		expect((Progress.canBuyRoom({ Stars = "lots", Cash = {}, Rooms = 3 }, Rooms.BathRoom, "BathRoom"))).toBe(false)
	end)
end)

T.describe("Progress.nextGoal", function()
	test("a new clinic aims at the Bath Room", function()
		expect(Progress.nextGoal(save(0, 0), Rooms, Upgrades)).toEqual({ Kind = "Room", Id = "BathRoom" })
	end)

	test("aims at the cheapest room in stars that isn't owned", function()
		expect(Progress.nextGoal(save(12, 0, { "BathRoom" }), Rooms, Upgrades)).toEqual({ Kind = "Room", Id = "Ward" })
	end)

	test("skips the winter room out of season", function()
		local data = save(50, 0, { "BathRoom", "Ward" })
		expect(Progress.nextGoal(data, Rooms, Upgrades)).toEqual({ Kind = "Room", Id = "Garden" })
		expect(Progress.nextGoal(data, Rooms, Upgrades, true)).toEqual({ Kind = "Room", Id = "WinterWing" })
	end)

	test("with every room owned, aims at the cheapest upgrade", function()
		local data = save(99, 0, ALL_ROOMS)
		expect(Progress.nextGoal(data, Rooms, Upgrades)).toEqual({ Kind = "Upgrade", Id = "Speed" })
		data.Upgrades.Speed = 1 -- next Speed is 150; Chairs and Tips tie at 75, Order breaks the tie
		expect(Progress.nextGoal(data, Rooms, Upgrades)).toEqual({ Kind = "Upgrade", Id = "Chairs" })
	end)

	test("out of winter, an unowned winter room doesn't block the upgrades", function()
		local data = save(99, 0, ALL_BUT_WINTER)
		expect(Progress.nextGoal(data, Rooms, Upgrades).Kind).toBe("Upgrade")
	end)

	test("is None when everything is owned and maxed", function()
		local data = save(999, 0, ALL_ROOMS)
		for _, id in Upgrades.Order do
			data.Upgrades[id] = #Upgrades[id].Prices
		end
		expect(Progress.nextGoal(data, Rooms, Upgrades)).toEqual({ Kind = "None", Id = "" })
	end)

	test("never errors on junk", function()
		expect(Progress.nextGoal(nil, Rooms, Upgrades)).toEqual({ Kind = "None", Id = "" })
		expect(Progress.nextGoal({}, Rooms, Upgrades).Kind).toBe("Room")
	end)
end)

T.describe("Progress.unlockedBetween", function()
	test("lists rooms whose stars were just reached", function()
		expect(Progress.unlockedBetween(Rooms, 9, 10)).toEqual({ "BathRoom" })
		expect(Progress.unlockedBetween(Rooms, 0, 30)).toEqual({ "BathRoom", "Ward" })
	end)

	test("is empty when no line was crossed", function()
		expect(Progress.unlockedBetween(Rooms, 10, 12)).toEqual({})
		expect(Progress.unlockedBetween(Rooms, 12, 12)).toEqual({})
		expect(Progress.unlockedBetween(Rooms, 30, 20)).toEqual({})
	end)

	test("never lists the free Stand", function()
		expect(Progress.unlockedBetween(Rooms, -1, 0)).toEqual({})
	end)
end)

T.describe("Progress.parseSlotKey", function()
	test("reads a known room and slot number", function()
		local roomId, index = Progress.parseSlotKey(Rooms, "Stand:1")
		expect(roomId).toBe("Stand")
		expect(index).toBe(1)
		expect((Progress.parseSlotKey(Rooms, "Garden:3"))).toBe("Garden")
	end)

	test("rejects a slot number the room doesn't have", function()
		expect((Progress.parseSlotKey(Rooms, "Stand:0"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:3"))).toBeNil() -- the Stand has 2 decor slots
		expect((Progress.parseSlotKey(Rooms, "BathRoom:2"))).toBeNil()
	end)

	test("rejects unknown rooms, including the Order list", function()
		expect((Progress.parseSlotKey(Rooms, "Moon:1"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Order:1"))).toBeNil()
	end)

	test("only accepts the one canonical spelling", function()
		expect((Progress.parseSlotKey(Rooms, "Stand:01"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, " Stand:1"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:1 "))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:1:2"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:-1"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:1.0"))).toBeNil()
	end)

	test("rejects junk without erroring", function()
		expect((Progress.parseSlotKey(Rooms, nil))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, 42))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, { "Stand:1" }))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, ""))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, string.rep("A", 5000) .. ":1"))).toBeNil()
		expect((Progress.parseSlotKey(Rooms, "Stand:" .. string.rep("9", 400)))).toBeNil()
	end)
end)
