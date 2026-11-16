--!nocheck
-- The HUD's zone map (Logic/HudZones; look build plan §B7; ux-cohesion-audit §3.1). The cases are the audit's table.

local T = require("./expect")
local expect, test = T.expect, T.test

local HudZones = require("../src/shared/Logic/HudZones")

local PHONES = { { 800, 360 }, { 667, 375 }, { 844, 390 }, { 932, 430 } }
local SCREENS = {
	{ 800, 360 },
	{ 667, 375 },
	{ 844, 390 },
	{ 932, 430 },
	{ 1024, 600 },
	{ 1280, 720 },
	{ 1366, 768 },
	{ 1920, 1080 },
	{ 1024, 768 },
	{ 2560, 1440 },
}

local function overlaps(a, b): boolean
	return a.X0 < b.X1 and b.X0 < a.X1 and a.Y0 < b.Y1 and b.Y0 < a.Y1
end

T.describe("HudZones: every piece has one zone and one slot", function()
	test("every piece is in exactly one zone", function()
		local pieces = {
			"Settings",
			"Cash",
			"Stars",
			"Now",
			"Clock",
			"Event",
			"Visitor",
			"Boosts",
			"Shop",
			"Nurses",
			"Book",
			"Badges",
			"Boards",
			"Gifts",
			"Goals",
			"Mailbox",
			"Hands",
		}
		local zones = { System = 0, Wallet = 0, Now = 0, Status = 0, LeftRail = 0, RightRail = 0, Bottom = 0 }
		local count = 0
		for piece, zone in HudZones.ZONE do
			count += 1
			expect(zones[zone] ~= nil).toBe(true)
			zones[zone] += 1
			expect(table.find(pieces, piece) ~= nil).toBe(true)
		end
		expect(count).toBe(#pieces)
		expect(zones).toEqual({ System = 1, Wallet = 2, Now = 1, Status = 4, LeftRail = 5, RightRail = 3, Bottom = 1 })
	end)

	test("the rails' order, and every rail piece's zone matches its rail", function()
		expect(HudZones.ORDER.LeftRail).toEqual({ "Shop", "Nurses", "Book", "Badges", "Boards" })
		expect(HudZones.ORDER.RightRail).toEqual({ "Gifts", "Goals", "Mailbox" })
		for rail, list in HudZones.ORDER do
			for _, piece in list do
				expect(HudZones.ZONE[piece]).toBe(rail)
			end
		end
	end)

	test("the constants (ux audit §3.4 Zone)", function()
		expect(HudZones.PHONE_BREAK).toBe(440)
		expect(HudZones.RAIL_BUTTON).toBe(72)
		expect(HudZones.RAIL_BUTTON_MIN).toBe(56)
		expect(HudZones.RAIL_GAP).toBe(10)
		expect(HudZones.RAIL_GAP_PHONE).toBe(8)
		expect(HudZones.CORNER_CLEAR).toBe(110)
		expect(HudZones.TOPBAR).toBe(58)
		expect(HudZones.WALLET_HEIGHT).toBe(112)
		expect(HudZones.NOW_HEIGHT).toBe(88)
		expect(HudZones.NOW_HEIGHT_SHORT).toBe(76)
		expect(HudZones.NOW_TAB).toBe(24)
		expect(HudZones.NOW_SLIM).toBe(44)
		expect(HudZones.STATUS_WIDTH).toBe(260)
		expect(HudZones.WALLET_WIDTH <= HudZones.STATUS_WIDTH).toBe(true) -- the Now card clears both columns
	end)
end)

T.describe("HudZones.layout", function()
	test(
		"phones: exactly 3 a side at 56 px, no captions, Badges and Boards in More, the wallet in the top bar",
		function()
			for _, size in PHONES do
				local layout = HudZones.layout(size[1], size[2])
				expect(layout.Phone).toBe(true)
				expect(layout.Left).toEqual({ "Shop", "Nurses", "Book" })
				expect(layout.Right).toEqual({ "Gifts", "Goals", "Mailbox" })
				expect(layout.More).toEqual({ "Badges", "Boards" })
				expect(layout.Button).toBe(56)
				expect(layout.Gap).toBe(8)
				expect(layout.Captions).toBe(false)
				expect(layout.WalletInTopbar).toBe(true)
				expect(layout.Margin).toBe(8)
			end
		end
	)

	test("the phone band: top bar + 8 down to 110 above the bottom (184 px at 360)", function()
		local layout = HudZones.layout(800, 360)
		expect(layout.Band.Top).toBe(58 + 8)
		expect(layout.Band.Bottom).toBe(360 - 110)
		expect(layout.Band.Bottom - layout.Band.Top).toBe(184)
		expect(3 * 56 + 2 * 8).toBe(184) -- exactly three fit
		expect(HudZones.layout(932, 430).Band.Bottom - HudZones.layout(932, 430).Band.Top).toBe(254)
	end)

	test("1280 x 720: all 5 on the left at 72 with captions, the wallet above them", function()
		local layout = HudZones.layout(1280, 720)
		expect(layout.Phone).toBe(false)
		expect(layout.Left).toEqual({ "Shop", "Nurses", "Book", "Badges", "Boards" })
		expect(layout.More).toEqual({})
		expect(layout.Right).toEqual({ "Gifts", "Goals", "Mailbox" })
		expect(layout.Button).toBe(72)
		expect(layout.Gap).toBe(10)
		expect(layout.Captions).toBe(true)
		expect(layout.WalletInTopbar).toBe(false)
		expect(layout.Margin).toBe(16)
		expect(layout.Band.Top >= 58 + 8 + HudZones.WALLET_HEIGHT).toBe(true) -- under the wallet
	end)

	test("1024 x 600: 4 on the left, Boards in More", function()
		local layout = HudZones.layout(1024, 600)
		expect(layout.Phone).toBe(false)
		expect(layout.Left).toEqual({ "Shop", "Nurses", "Book", "Badges" })
		expect(layout.More).toEqual({ "Boards" })
		expect(layout.Button >= 56 and layout.Button <= 72).toBe(true)
		expect(#layout.Right).toBe(3)
	end)

	test("the phone break is a safe height under 440", function()
		expect(HudZones.layout(1000, 439).Phone).toBe(true)
		expect(HudZones.layout(1000, 440).Phone).toBe(false)
	end)

	test("every screen: buttons 56..72, at least 3 a side, every left piece shown once (rail or More)", function()
		for _, size in SCREENS do
			local layout = HudZones.layout(size[1], size[2])
			expect(layout.Button >= 56 and layout.Button <= 72).toBe(true)
			expect(#layout.Left >= 3).toBe(true)
			expect(#layout.Right).toBe(3)
			expect(#layout.Left + #layout.More).toBe(5)
			local seen = {}
			for _, piece in layout.Left do
				seen[piece] = (seen[piece] or 0) + 1
			end
			for _, piece in layout.More do
				seen[piece] = (seen[piece] or 0) + 1
			end
			for _, piece in HudZones.ORDER.LeftRail do
				expect(seen[piece]).toBe(1)
			end
			-- slots keep the rail's order: what's shown is a prefix of ORDER
			for index, piece in layout.Left do
				expect(piece).toBe(HudZones.ORDER.LeftRail[index])
			end
		end
	end)

	test("no rail slot reaches the bottom corners, leaves the band, or meets the Now card", function()
		for _, size in SCREENS do
			local w, h = size[1], size[2]
			local layout = HudZones.layout(w, h)
			local now = HudZones.nowRect(layout, w)
			for side, list in { Left = layout.Left, Right = layout.Right } do
				for index in list do
					local rect = HudZones.railRect(layout, side, index, w)
					expect(rect.Y1 <= h - HudZones.CORNER_CLEAR).toBe(true)
					expect(rect.Y0 >= layout.Band.Top).toBe(true)
					expect(rect.X0 >= 0 and rect.X1 <= w).toBe(true)
					expect(overlaps(rect, now)).toBe(false)
				end
			end
			-- the two rails hug opposite edges
			local left = HudZones.railRect(layout, "Left", 1, w)
			local right = HudZones.railRect(layout, "Right", 1, w)
			expect(left.X0).toBe(layout.Margin)
			expect(right.X1).toBe(w - layout.Margin)
		end
	end)

	test("slots are fixed: a slot's rect doesn't depend on which pieces are revealed", function()
		local layout = HudZones.layout(1280, 720)
		local first = HudZones.railRect(layout, "Left", 3, 1280)
		local again = HudZones.railRect(HudZones.layout(1280, 720), "Left", 3, 1280)
		expect(first).toEqual(again)
		local second = HudZones.railRect(layout, "Left", 2, 1280)
		expect(first.Y0 - second.Y0).toBe(layout.Button + layout.Gap)
	end)

	test(
		"the Now card: 88 tall (76 on a screen under 500), never wider than 480, clear of both side columns",
		function()
			expect(HudZones.layout(1280, 720).NowHeight).toBe(88)
			expect(HudZones.layout(844, 390).NowHeight).toBe(76)
			expect(HudZones.layout(1024, 499).NowHeight).toBe(76)
			expect(HudZones.layout(1024, 500).NowHeight).toBe(88)
			for _, size in SCREENS do
				local w = size[1]
				local layout = HudZones.layout(w, size[2])
				local now = HudZones.nowRect(layout, w)
				expect(layout.NowWidth <= 480).toBe(true)
				expect(layout.NowWidth >= 240).toBe(true) -- still room for a card on the narrowest phone
				-- the side columns: the wallet (left) and Status (right), each `StatusWidth` wide at most
				expect(now.X0 >= layout.Margin + layout.StatusWidth + 8 - 0.01).toBe(true)
				expect(now.X1 <= w - layout.Margin - layout.StatusWidth - 8 + 0.01).toBe(true)
			end
			expect(HudZones.layout(1280, 720).NowWidth).toBe(480)
		end
	)

	test("a custom top bar moves the band; junk sizes fall back instead of erroring", function()
		expect(HudZones.layout(800, 360, 36).Band.Top).toBe(36 + 8)
		expect(HudZones.layout(800, 360, nil).Top).toBe(58)
		local layout = HudZones.layout(0 / 0, -5)
		expect(layout.Button >= 56).toBe(true)
		expect(#layout.Left >= 3).toBe(true)
	end)
end)

T.describe("HudZones.nowWidth", function()
	test("min(480, safeW - 2 x (walletRight + 8))", function()
		expect(HudZones.nowWidth(1280, 276)).toBe(480)
		expect(HudZones.nowWidth(844, 188)).toBe(844 - 2 * 196)
		expect(HudZones.nowWidth(667, 188)).toBe(667 - 2 * 196)
	end)

	test("it never covers the wallet: the centred card starts right of walletRight + 8", function()
		for _, w in { 480, 667, 800, 844, 932, 1024, 1280, 1920 } do
			for _, walletRight in { 60, 120, 188, 240, 276, 400 } do
				local width = HudZones.nowWidth(w, walletRight)
				expect(width >= 0).toBe(true)
				expect(width <= 480).toBe(true)
				if width > 0 then
					expect((w - width) / 2 >= walletRight + 8 - 0.01).toBe(true)
				end
			end
		end
		expect(HudZones.nowWidth(300, 200)).toBe(0) -- no room at all: no card, never a negative width
	end)
end)
