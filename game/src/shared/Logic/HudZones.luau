--!strict
-- The HUD's zone map in numbers (look build plan §B7; docs/research/2026-11-16-ux-cohesion-audit.md §3.1). Pure: no
-- Roblox services and no requires, so Lune can test it. UI/Hud lays the screen out from `layout` on every resize;
-- UI/Theme mirrors the constants as Theme.Zone.
--
-- The rules:
--   · Every HUD piece belongs to exactly ONE zone (ZONE), and its slot never changes (ORDER). A piece that isn't
--     revealed yet leaves its slot empty: nothing ever jumps to a new place.
--   · Phones (a safe height under PHONE_BREAK) get exactly 3 a side at 56 px with no captions: 🛒 👩‍⚕️ 📖 on the
--     left, 🎁 🎯 📬 on the right. 🏅 Badges and 🏆 Top go into ⚙️ More, and the wallet moves into the top-bar row.
--     A phone whose safe height is under 360 (a bottom inset, or a very small phone) can't fit 3 x 56 + 2 x 8 above
--     the corners: the gap shrinks first (down to RAIL_GAP_MIN), and under that only the plates that fit stay on
--     each rail; the rest (📖, 📬, then 👩‍⚕️, 🎯) go into ⚙️ More too. The corners always win.
--   · Desktop and tablet put the wallet top-left, above the left rail. The left rail shows as many of its 5 as fit
--     at >= 56 px (<= 72) with captions, at least 3; the rest go into ⚙️ More. The right rail always shows 3.
--   · The rail band runs from the top bar + 8 (plus the wallet and a gap on desktop) down to CORNER_CLEAR above the
--     bottom. Nothing is ever in the bottom corners (the thumbstick and jump on touch).
--
--   HudZones.ZONE: { [Piece]: Zone }
--   HudZones.ORDER = { LeftRail = { ... }, RightRail = { ... } }
--   HudZones.layout(safeW, safeH, topbar?): Layout        sizes are px; safeW x safeH is the screen, `topbar` the
--                                                         Roblox top-bar row's height (TOPBAR when nil)
--   HudZones.nowWidth(safeW, walletRight): number         min(480, safeW - 2 x (walletRight + 8)), never negative:
--                                                         the centred Now card never covers a side column that
--                                                         ends `walletRight` px from its edge
--   HudZones.railRect(layout, side, index, safeW): Rect   slot `index` of "Left" | "Right" (px from the top left)
--   HudZones.nowRect(layout, safeW): Rect                 the Now card at its tallest (the card + its tab)
-- Foundation additions to the plan's list (T5 needed numbers the plan left open): WALLET_WIDTH, STATUS_WIDTH_PHONE,
-- NOW_MAX, the Layout fields Top (the top bar used), StatusWidth, NowHeight and RailTop, railRect and nowRect.

local HudZones = {}

export type Zone = "System" | "Wallet" | "Now" | "Status" | "LeftRail" | "RightRail" | "Bottom"
export type Piece = string
export type Rect = { X0: number, Y0: number, X1: number, Y1: number }
export type Layout = {
	Phone: boolean,
	Button: number, -- a rail button's side
	Gap: number, -- between rail buttons
	Captions: boolean,
	WalletInTopbar: boolean,
	Left: { Piece }, -- the left rail, top to bottom
	Right: { Piece },
	More: { Piece }, -- moved into ⚙️ More (the left rail's first, then the right rail's on a very short phone)
	Band: { Top: number, Bottom: number }, -- the rails' band, px from the screen top
	RailTop: number, -- the first slot's top (the left rail's column centred in the band)
	Margin: number, -- from the screen edge
	Top: number, -- the top bar's height used
	NowWidth: number,
	NowHeight: number, -- the Now card's body (its tab adds NOW_TAB)
	StatusWidth: number,
}

HudZones.PHONE_BREAK = 440 -- a safe height under this is a phone
HudZones.RAIL_BUTTON = 72 -- desktop and tablet, at most
HudZones.RAIL_BUTTON_MIN = 56 -- the tap minimum, and the phone's size
HudZones.RAIL_GAP = 10
HudZones.RAIL_GAP_PHONE = 8
HudZones.RAIL_GAP_MIN = 4 -- a short phone squeezes the gap to this before a plate leaves the rail
HudZones.CORNER_CLEAR = 110 -- kept free above the bottom edge (measure it in the Device Simulator)
HudZones.TOPBAR = 58 -- the fallback; read GuiService.TopbarInset
HudZones.WALLET_HEIGHT = 112 -- desktop: 💰 and ⭐ stacked
HudZones.WALLET_WIDTH = 240 -- desktop: never wider than the Status column, so the Now card clears both
HudZones.NOW_HEIGHT = 88
HudZones.NOW_HEIGHT_SHORT = 76 -- on a screen under NOW_SHORT_BREAK px tall
HudZones.NOW_SHORT_BREAK = 500
HudZones.NOW_TAB = 24 -- the "TUTORIAL n/7" tab above the card
HudZones.NOW_SLIM = 44 -- the slim strip (during the mini-game)
HudZones.NOW_MAX = 480
HudZones.STATUS_WIDTH = 260
HudZones.STATUS_WIDTH_PHONE = 180
HudZones.MARGIN = 16
HudZones.MARGIN_PHONE = 8
HudZones.MIN_RAIL = 3 -- a rail never shows fewer

HudZones.ZONE = table.freeze({
	Settings = "System",
	Cash = "Wallet",
	Stars = "Wallet",
	Now = "Now",
	Clock = "Status",
	Event = "Status",
	Visitor = "Status",
	Boosts = "Status",
	Shop = "LeftRail",
	Nurses = "LeftRail",
	Book = "LeftRail",
	Badges = "LeftRail",
	Boards = "LeftRail",
	Gifts = "RightRail",
	Goals = "RightRail",
	Mailbox = "RightRail",
	Hands = "Bottom",
}) :: { [Piece]: Zone }

HudZones.ORDER = table.freeze({
	LeftRail = table.freeze({ "Shop", "Nurses", "Book", "Badges", "Boards" }),
	RightRail = table.freeze({ "Gifts", "Goals", "Mailbox" }),
})

local function positive(value: any, fallback: number): number
	return if type(value) == "number" and value == value and value > 0 then value else fallback
end

function HudZones.nowWidth(safeW: number, walletRight: number): number
	return math.max(0, math.min(HudZones.NOW_MAX, safeW - 2 * (walletRight + 8)))
end

function HudZones.layout(safeW: number, safeH: number, topbar: number?): Layout
	local width, height = positive(safeW, 1280), positive(safeH, 720)
	local top = if type(topbar) == "number" and topbar == topbar and topbar >= 0 then topbar else HudZones.TOPBAR
	local phone = height < HudZones.PHONE_BREAK
	local gap = if phone then HudZones.RAIL_GAP_PHONE else HudZones.RAIL_GAP
	local margin = if phone then HudZones.MARGIN_PHONE else HudZones.MARGIN
	local bandTop = top + 8 + (if phone then 0 else HudZones.WALLET_HEIGHT + gap)
	local bandBottom = math.max(bandTop, height - HudZones.CORNER_CLEAR)
	local room = bandBottom - bandTop

	local order = HudZones.ORDER.LeftRail
	local count = HudZones.MIN_RAIL
	local button = HudZones.RAIL_BUTTON_MIN
	if not phone then
		-- As many of the five as fit at 56 px or more, each as big as the band allows (at most 72).
		for n = #order, HudZones.MIN_RAIL, -1 do
			local side = math.min(HudZones.RAIL_BUTTON, math.floor((room - (n - 1) * gap) / n))
			if side >= HudZones.RAIL_BUTTON_MIN or n == HudZones.MIN_RAIL then
				count = n
				button = math.max(side, HudZones.RAIL_BUTTON_MIN)
				break
			end
		end
	end

	local rightCount = #HudZones.ORDER.RightRail
	if phone and room < count * button + (count - 1) * gap then
		-- A short phone: squeeze the gap, and if three still don't fit, keep only the plates that do.
		local squeezed = math.floor((room - count * button) / (count - 1))
		if squeezed >= HudZones.RAIL_GAP_MIN then
			gap = squeezed
		else
			count = math.clamp(math.floor((room + gap) / (button + gap)), 1, HudZones.MIN_RAIL)
			rightCount = math.min(rightCount, count)
		end
	end

	local left: { Piece }, right: { Piece }, more: { Piece } = {}, {}, {}
	for index, piece in order do
		table.insert(if index <= count then left else more, piece)
	end
	for index, piece in HudZones.ORDER.RightRail do
		table.insert(if index <= rightCount then right else more, piece)
	end
	local railHeight = count * button + (count - 1) * gap
	local statusWidth = if phone then HudZones.STATUS_WIDTH_PHONE else HudZones.STATUS_WIDTH
	return {
		Phone = phone,
		Button = button,
		Gap = gap,
		Captions = not phone,
		WalletInTopbar = phone,
		Left = left,
		Right = right,
		More = more,
		Band = { Top = bandTop, Bottom = bandBottom },
		RailTop = bandTop + math.max(0, math.floor((room - railHeight) / 2)),
		Margin = margin,
		Top = top,
		NowWidth = HudZones.nowWidth(width, margin + statusWidth),
		NowHeight = if height < HudZones.NOW_SHORT_BREAK then HudZones.NOW_HEIGHT_SHORT else HudZones.NOW_HEIGHT,
		StatusWidth = statusWidth,
	}
end

-- Slot `index` (1 = the top) of a rail. A slot keeps its rect whether or not its piece is revealed.
function HudZones.railRect(layout: Layout, side: "Left" | "Right", index: number, safeW: number): Rect
	local x0 = if side == "Left" then layout.Margin else safeW - layout.Margin - layout.Button
	local y0 = layout.RailTop + (index - 1) * (layout.Button + layout.Gap)
	return { X0 = x0, Y0 = y0, X1 = x0 + layout.Button, Y1 = y0 + layout.Button }
end

-- The Now card at its tallest: its tab, then the card, under the top bar, centred.
function HudZones.nowRect(layout: Layout, safeW: number): Rect
	local x0 = (safeW - layout.NowWidth) / 2
	local y0 = layout.Top + 8
	return { X0 = x0, Y0 = y0, X1 = x0 + layout.NowWidth, Y1 = y0 + HudZones.NOW_TAB + layout.NowHeight }
end

return HudZones
