--!strict
-- BeltView (depth-update design §2, build plan §B4/§B9; memory-20261116-012/-013). OWNER: T4.
-- The shared Nurse Belt as THIS player sees it: smooth riders, a Hire card over each one, the odds popup, and the
-- Golden Hour / Night Rush / big-arrival banners.
--   init(ctx)   binds Workspace.NurseBelt (and a belt that replaces it later); listens for the bus "Shout" and
--               "Open" ("NurseOdds"); watches the Workspace attributes GoldenHour, NightRush (IsNight when
--               NurseBelt hasn't set it) and BeltPity; fires "Banner" (Types.BannerSpec) and
--               "Sound" (Arrival, Golden, Pop; the Hire cue comes with NurseNews in Feel/Sounds)
--
-- Riders (Workspace.NurseBelt.Riders.Rider_<RiderId>):
--   · Smooth: every frame each rider's Root goes to BeltStart:Lerp(BeltEnd, Logic/Belt.alpha(StartAt, now,
--     RideSeconds)) here on the client (the server only moves it once a second), keeping the server's rotation, with
--     a tiny ride bounce (none with reduced motion). Hired riders, riders at the end and riders tagged CreatureMotion
--     are left to the server (they hop off). The frame loop runs only while the camera is within MOVE_MAX_DISTANCE
--     of the belt (the 4 Hz card loop checks); both stop when no rider is left.
--   · Cards: one BillboardGui per rider in PlayerGui (Adornee = its Root, so it takes taps), shown only while you
--     stand within HireDistance + CHIP_MARGIN studs of it, so the belt never covers the clinics round the plaza.
--     Phone first: the rider you tapped, or whose prompt is up, or the nearest one within FOCUS_REACH, shows the
--     FULL card (drawn on top, a fixed pixel size): the rarity band
--     and frame (Kit.rarityFrame), its name, the role icon and level-1 stat (Logic/Nurse.stats), "⬆️ Lv n" when you
--     own it, a NEW! sticker until it's in your Journal as hired, and a big Hire button with YOUR price
--     (Logic/Belt.price at your hospital level). Every other rider shows a small chip (its icon and your price),
--     sized in studs (it shrinks with distance, never above CHIP_SIZE px) and not on top, so the world hides it;
--     tap one to open its card. Hired riders show ✅; yours at max level show ⭐ MAX.
--   · Hire: the button asks HireNurse (Hud.ask). Too far or short of cash, it explains instead of asking (the
--     server still checks everything). Its HirePrompt (keyboard E, gamepad) gets the Custom style, so the card is
--     the prompt's look: the key shows on the card's button while the prompt is up. Its ObjectText is your price.
--   · Glow: Epic and up get a soft PointLight (no shadows) and a few sparkles in the rarity's colour, unless the
--     model already has its own (NurseBuilder's RarityGlow / RarityFX). Reduced motion switches every sparkle on a
--     rider off here (NurseBuilder's too, client-only) and stops the card's halo pulse.
-- The odds popup ("🎲 Odds", a Hud.modal Popup over any panel): every rarity's odds by day, in Night Rush and in
-- Golden Hour (now's column marked), your price for each, and the pity count (BeltPity). A 🎲 chip floats over the
-- belt's Sign to open it (it reads 🌙 / 👑 during the events, never a clock); UI/NursePanel opens it too
-- (ctx.fire("Open", "NurseOdds")).
-- Banners (UI/Toasts shows them): Golden Hour (once per window, for a few seconds, with the real Secret odds), Night
-- Rush (8 s when the night starts), an Epic+ arrival and a Legendary+ hire from "Shout". None while the first-session
-- tutorial runs (or before the first snapshot); a Golden Hour still running when it ends shows then.
-- Cash only, odds on show, nothing pressures a kid (red line 3): no "hurry" words, no flashing prices, and no
-- countdowns at all: not to the next Golden Hour, not to the end of one or of a Night Rush.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Logic = Shared:WaitForChild("Logic")
local BeltLogic = require(Logic:WaitForChild("Belt"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local TutorialLogic = require(Logic:WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BeltView = {}

local REFRESH_SECONDS = 0.25 -- the card loop (focus, distance, prices); the movement itself is every frame
local FOCUS_REACH = 30 -- studs: the nearest rider this close shows its full card
local CARD_MAX_DISTANCE = 110 -- studs: cards fade out past this
local INFO_MAX_DISTANCE = 160
local MOVE_MAX_DISTANCE = 320 -- studs from the camera: farther riders keep the server's 1 s steps
local BOUNCE_HEIGHT = 0.2
local BOUNCE_SECONDS = 0.85
local HALO = 6 -- px of rarity halo round the full card
local FULL_SIZE = Vector2.new(176, 164)
local CHIP_SIZE = Vector2.new(120, 64) -- px: the most a chip ever shows (up close)
local CHIP_STUDS = Vector2.new(6, 3.2) -- the chip's canvas in studs (the same shape), so it shrinks with distance
local CHIP_MARGIN = 10 -- studs past Config.Belt.HireDistance that a rider's chip still shows
local SOFT_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- built in (as Feel/Atmosphere)
local NIGHT_BANNER_SECONDS = 8
local GOLDEN_BANNER_SECONDS = 6
local ARRIVAL_BANNER_SECONDS = 5
local HIRED_BANNER_SECONDS = 4

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types, only BeltLogic / NurseLogic / TutorialLogic (pure themselves). A scratch
-- Lune harness loads the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.ROLE_ICONS = { Maker = "🛠️", Healer = "🩺", Cheerer = "🎉" } :: { [string]: string }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- "70%", "39.5%", "0.25%"; "–" when it can't come now (0 or junk).
function Pure.percent(value: any): string
	if not finite(value) or value <= 0 then
		return "–"
	end
	local hundredths = math.floor(value * 100 + 0.5)
	if hundredths <= 0 then
		return "<0.01%"
	elseif hundredths % 100 == 0 then
		return string.format("%d%%", hundredths // 100)
	elseif hundredths % 10 == 0 then
		return string.format("%.1f%%", hundredths / 100)
	end
	return string.format("%.2f%%", hundredths / 100)
end

-- A countdown: "1:05", "12:00", "1:02:03". Never below 0:00; seconds round up (so 0:00 means it's over).
function Pure.clock(seconds: any): string
	local s = if finite(seconds) then math.max(0, math.ceil(seconds)) else 0
	local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- A short price for small chips: 1,500 · 9,999 · 20K · 112.5K · 1.2M.
function Pure.short(n: any): string
	local value = if finite(n) then math.max(0, math.floor(n + 0.5)) else 0
	if value >= 1e6 then
		return (string.gsub(string.format("%.1fM", value / 1e6), "%.0M", "M"))
	elseif value >= 1e4 then
		return (string.gsub(string.format("%.1fK", value / 1e3), "%.0K", "K"))
	end
	local digits = tostring(value)
	return (string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)(%d)", "%1,%2"))))
end

local function secondsText(value: number): string
	local tenths = math.floor(value * 10 + 0.5)
	if tenths % 10 == 0 then
		return tostring(tenths // 10) .. "s"
	end
	return string.format("%.1fs", tenths / 10)
end

local function share(multiplier: number): string
	return tostring(math.floor((multiplier - 1) * 100 + 0.5)) .. "%"
end

-- The stat line under a nurse's name: Maker/Healer "⏱️14s" (one item / one treat this often), Cheerer
-- "⏳+10% 💰+5%" (patience and tips). From Logic/Nurse.stats, so it always matches the server.
function Pure.statText(role: string, rarity: string, level: number, cfg: any): string
	local stats = NurseLogic.stats(role, rarity, level, cfg)
	if role == "Cheerer" then
		return "⏳+" .. share(stats.Patience) .. " 💰+" .. share(stats.Tip)
	end
	local every = stats.Every
	if every then
		return "⏱️" .. secondsText(every)
	end
	return ""
end

-- What a rider's Hire button does for this viewer, first match wins: "Hired" (someone took it) · "Max" (yours is at
-- the top level) · "Far" (no character, or past HireDistance less a stud of slack) · "Poor" (short of cash) · "Ready".
function Pure.hireState(hired: boolean, entry: any, cfg: any, cash: any, price: number, distance: number?): string
	if hired then
		return "Hired"
	end
	if not BeltLogic.canHire(entry, cfg) then
		return "Max"
	end
	local belt = if type(cfg) == "table" and type(cfg.Belt) == "table" then cfg.Belt else {}
	local reach = if finite(belt.HireDistance) then belt.HireDistance else 40
	if distance == nil or not finite(distance) or distance > reach - 1 then
		return "Far"
	end
	if not finite(cash) or cash < price then
		return "Poor"
	end
	return "Ready"
end

export type Candidate = { Id: number, Distance: number, Open: boolean }

-- Which rider shows its full card, first match wins: the one whose Hire prompt is up (E hires it) · the one you
-- tapped (while it's still here) · the current one while it's open, in reach and at most 3 studs farther than the
-- nearest (so the card doesn't flick between two neighbours) · the nearest open one in reach · none.
function Pure.focus(
	candidates: { Candidate },
	prompted: number?,
	tapped: number?,
	current: number?,
	reach: number
): number?
	local byId: { [number]: Candidate } = {}
	local best: Candidate? = nil
	for _, candidate in candidates do
		byId[candidate.Id] = candidate
		if candidate.Open and candidate.Distance <= reach then
			if best == nil or candidate.Distance < best.Distance then
				best = candidate
			end
		end
	end
	if prompted and byId[prompted] then
		return prompted
	end
	if tapped and byId[tapped] then
		return tapped
	end
	local held = if current then byId[current] else nil
	if held and best and held.Open and held.Distance <= reach and held.Distance <= best.Distance + 3 then
		return held.Id
	end
	return if best then best.Id else nil
end

-- Night Rush: NurseBelt mirrors IsNight into NightRush; before it does (or without it), IsNight decides.
function Pure.nightRush(nightRush: any, isNight: any): boolean
	if type(nightRush) == "boolean" then
		return nightRush
	end
	return isNight == true
end

-- Which odds column is now: "Golden" (Golden Hour, day or night) · "Night" (Night Rush) · "Day".
function Pure.mode(golden: boolean, night: boolean): string
	return if golden then "Golden" elseif night then "Night" else "Day"
end

-- Banners wait while the first-session tutorial runs (steps 1-8) and before the first snapshot (0).
function Pure.quiet(step: any): boolean
	return not TutorialLogic.isDone(step)
end

export type OddsRow = { Rarity: string, Day: number, Night: number, Golden: number, Price: number }

-- The odds popup: one row per rarity, lowest first. Golden is Golden Hour at the current time of day (so at night
-- it carries the Night Rush boost too), exactly what the belt would roll.
function Pure.oddsRows(cfg: any, rarities: { string }, night: boolean, level: number): { OddsRow }
	local day = BeltLogic.odds(cfg, false, false)
	local rush = BeltLogic.odds(cfg, true, false)
	local golden = BeltLogic.odds(cfg, night, true)
	local rows: { OddsRow } = {}
	for _, rarity in rarities do
		table.insert(rows, {
			Rarity = rarity,
			Day = day[rarity] or 0,
			Night = rush[rarity] or 0,
			Golden = golden[rarity] or 0,
			Price = BeltLogic.price(cfg, rarity, level),
		})
	end
	return rows
end
-- PURE-END

BeltView.Pure = Pure -- for a scratch harness and for UI/NursePanel's shared wording

------------------------------------------------------------------------------------------------------------------
-- Look helpers
------------------------------------------------------------------------------------------------------------------

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 9
	limit.Parent = label
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in props do
		if key ~= "Parent" then
			(f :: any)[key] = value
		end
	end
	f.Parent = props.Parent
	return f
end

-- The shape outline Kit draws round a button (not the Contextual one round its text).
local function borderOf(gui: Instance): UIStroke?
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			return child
		end
	end
	return nil
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function keyLabel(prompt: ProximityPrompt): string?
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Touch then
		return nil
	elseif preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name <= 3 then name else nil
end

------------------------------------------------------------------------------------------------------------------
-- Riders
------------------------------------------------------------------------------------------------------------------

type Rider = {
	Id: number,
	Model: Model,
	Root: BasePart?,
	NurseId: string,
	Rarity: string,
	Role: string,
	Color: Color3,
	StartAt: number,
	Ride: number,
	Hired: boolean,
	Free: boolean, -- moved here (not hired, not handed to CreatureMotion)
	Open: boolean, -- still hireable on the belt
	Distance: number,
	Phase: number,
	PromptShown: boolean,
	Prompt: ProximityPrompt?,
	Busy: boolean,
	HireState: string,
	Price: number,
	Drawn: string,
	Full: boolean,
	Gui: BillboardGui?,
	Card: Frame?,
	FullFrame: Frame?,
	ChipFrame: Frame?,
	Halo: Frame?,
	HaloTween: Tween?,
	Band: TextLabel?,
	Sticker: TextLabel?,
	NameLabel: TextLabel?,
	Stat: TextLabel?,
	Button: TextButton?,
	Key: TextLabel?,
	Pill: TextLabel?,
	ChipIcon: TextLabel?,
	ChipPrice: TextLabel?,
	ChipDot: Frame?,
	Sparkles: { ParticleEmitter }, -- ours or NurseBuilder's: off here (client-only) with reduced motion
	Added: { Instance }, -- client-only things put on the rider's model (removed with it)
	Connections: { RBXScriptConnection },
}

function BeltView.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local player = ctx.Player
	local playerGui = player:WaitForChild("PlayerGui")
	local rarityOrder: { string } = data.Rarities.Order

	local riders: { [Model]: Rider } = {}
	local byId: { [number]: Rider } = {}
	local beltStart: BasePart? = nil
	local beltEnd: BasePart? = nil
	local beltConnections: { RBXScriptConnection } = {}
	local infoGui: BillboardGui? = nil
	local infoButton: TextButton? = nil
	local focusId: number? = nil
	local tappedId: number? = nil
	local moveConnection: RBXScriptConnection? = nil
	local looping = false

	local function rarityInfo(rarity: string): any
		return rawget(data.Rarities, rarity) or rawget(data.Rarities, "Common")
	end

	local function nightRush(): boolean
		return Pure.nightRush(Workspace:GetAttribute("NightRush"), Workspace:GetAttribute("IsNight"))
	end

	local function goldenHour(): boolean
		return Workspace:GetAttribute("GoldenHour") == true
	end

	local function journalMark(nurseId: string): any
		local index = ctx.State.NurseIndex
		return if type(index) == "table" then index[nurseId] else nil
	end

	local function myEntry(nurseId: string): any
		local nurses = ctx.State.Nurses
		return if type(nurses) == "table" then nurses[nurseId] else nil
	end

	local function myLevel(): number
		local level = ctx.State.Level
		return if type(level) == "number" then level else 1
	end

	--------------------------------------------------------------------------------------------------------------
	-- The odds popup
	--------------------------------------------------------------------------------------------------------------
	type OddsCells = { Row: Frame, Day: TextLabel, Night: TextLabel, Golden: TextLabel, Price: TextLabel }
	local odds: Hud.Modal? = nil
	local oddsCells: { [string]: OddsCells } = {}
	local oddsHeaders: { [string]: Frame } = {}
	local oddsStatus: TextLabel? = nil
	local oddsPity: TextLabel? = nil

	local COLUMNS = { "Day", "Night", "Golden", "Price" }
	local COLUMN_ICONS = { Day = "☀️", Night = "🌙", Golden = "👑", Price = "💰" }
	local NAME_SHARE = 0.36
	local CELL_SHARE = (1 - NAME_SHARE) / #COLUMNS

	local function cell(parent: Instance, column: number, text: string, bold: boolean): (Frame, TextLabel)
		local holder = frame({
			Name = "Cell" .. column,
			BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.55),
			BackgroundTransparency = 1,
			Position = UDim2.new(NAME_SHARE + CELL_SHARE * (column - 1), 2, 0, 0),
			Size = UDim2.new(CELL_SHARE, -4, 1, 0),
			Parent = parent,
		})
		Kit.corner(holder, 10)
		local label = Kit.label({
			Name = "Text",
			Text = text,
			TextScaled = true,
			Font = if bold then Theme.DisplayFont else Theme.Font,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -6, 1, -10),
			Parent = holder,
		})
		textLimit(label, 22)
		return holder, label
	end

	local function buildOdds(): Hud.Modal
		local modal = Hud.modal(ctx, {
			Name = "NurseOdds",
			Title = "🎲 Odds",
			Accent = Theme.Colors.Purple,
			Layer = "Popup",
			MaxSize = Vector2.new(500, 560),
		})
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Scroll"
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
		scroll.Selectable = false
		scroll.Parent = modal.Body
		local list = Kit.list(scroll, Enum.FillDirection.Vertical, 6)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 3)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = scroll

		-- What's on now, and the pity count.
		local status = frame({
			Name = "Status",
			BackgroundColor3 = Theme.Colors.Card,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 1,
			Parent = scroll,
		})
		Kit.corner(status, 14)
		Kit.stroke(status, Theme.Colors.Outline, 2)
		oddsStatus = Kit.label({
			Name = "Now",
			Text = "",
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(0.55, -10, 1, -12),
			Parent = status,
		})
		textLimit(oddsStatus :: TextLabel, 24)
		oddsPity = Kit.label({
			Name = "Pity",
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.new(0.45, -10, 1, -12),
			Parent = status,
		})
		textLimit(oddsPity :: TextLabel, 22)

		-- The table: a header row of icons, then one row per rarity.
		local head = frame({
			Name = "Head",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 2,
			Parent = scroll,
		})
		for index, column in COLUMNS do
			local holder = cell(head, index, COLUMN_ICONS[column], true)
			oddsHeaders[column] = holder
		end
		for order, rarity in rarityOrder do
			local info = rarityInfo(rarity)
			local color = hexColor(info.Color, Theme.Colors.Quiet)
			local row = frame({
				Name = rarity,
				BackgroundColor3 = Theme.Colors.Paper,
				Size = UDim2.new(1, 0, 0, 42),
				LayoutOrder = 2 + order,
				Parent = scroll,
			})
			Kit.corner(row, 12)
			Kit.rarityFrame(row, rarity)
			local chip = frame({
				Name = "Rarity",
				BackgroundColor3 = Kit.lighten(color, 0.1),
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(NAME_SHARE, -8, 1, -8),
				Parent = row,
			})
			Kit.corner(chip, 10)
			Palette.candyGradient(chip)
			local name = Kit.label({
				Name = "Name",
				Text = info.Icon .. " " .. info.Name,
				TextScaled = true,
				Outlined = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -6),
				Parent = chip,
			})
			textLimit(name, 20)
			local _, day = cell(row, 1, "", false)
			local _, night = cell(row, 2, "", false)
			local _, golden = cell(row, 3, "", false)
			local _, price = cell(row, 4, "", false)
			oddsCells[rarity] = { Row = row, Day = day, Night = night, Golden = golden, Price = price }
		end

		-- What the icons mean (≤ 6 words).
		local legend = Kit.label({
			Name = "Legend",
			Text = "🌙 Night Rush  ·  👑 Golden Hour",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 20,
			Parent = scroll,
		})
		textLimit(legend, 20)
		return modal
	end

	local function renderOdds()
		local modal = odds
		if not modal or not modal.isOpen() then
			return
		end
		local night = nightRush()
		local golden = goldenHour()
		local mode = Pure.mode(golden, night)
		for _, row in Pure.oddsRows(cfg, rarityOrder, night, myLevel()) do
			local cells = oddsCells[row.Rarity]
			if cells then
				cells.Day.Text = Pure.percent(row.Day)
				cells.Night.Text = Pure.percent(row.Night)
				cells.Golden.Text = Pure.percent(row.Golden)
				cells.Price.Text = "💰" .. Pure.short(row.Price)
				for _, column in { "Day", "Night", "Golden" } do
					local label = (cells :: any)[column] :: TextLabel
					local holder = label.Parent :: Frame
					holder.BackgroundTransparency = if column == mode then 0 else 1
					label.Font = if column == mode then Theme.DisplayFont else Theme.Font
				end
			end
		end
		for column, holder in oddsHeaders do
			holder.BackgroundTransparency = if column == mode then 0 else 1
		end
		local status = oddsStatus
		if status then
			if golden then
				status.Text = "👑 Golden Hour"
			elseif night then
				status.Text = "🌙 Night Rush"
			else
				status.Text = "☀️ Day"
			end
		end
		local pity = oddsPity
		if pity then
			local left = Workspace:GetAttribute("BeltPity")
			pity.Text = if type(left) == "number" and left > 0
				then "🎁 Rare+ in " .. math.floor(left)
				else "🎁 Rare+ next!"
		end
	end

	local function openOdds()
		local modal = odds or buildOdds()
		odds = modal
		modal.open()
		renderOdds()
	end

	--------------------------------------------------------------------------------------------------------------
	-- The 🎲 chip over the belt's sign
	--------------------------------------------------------------------------------------------------------------
	local function renderInfo()
		local button = infoButton
		if not button then
			return
		end
		if goldenHour() then
			button.Text = "👑 Golden Hour!"
		elseif nightRush() then
			button.Text = "🌙 Odds"
		else
			button.Text = "🎲 Odds"
		end
	end

	local function buildInfo(belt: Instance)
		if infoGui then
			infoGui:Destroy()
			infoGui = nil
			infoButton = nil
		end
		local sign = belt:FindFirstChild("Sign")
		local anchor: BasePart? = if sign and sign:IsA("BasePart") then sign else beltStart
		if not anchor then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "BeltOddsChip"
		gui.Adornee = anchor
		gui.AlwaysOnTop = true
		gui.Active = true
		gui.LightInfluence = 0
		gui.MaxDistance = INFO_MAX_DISTANCE
		gui.ResetOnSpawn = false
		gui.Size = UDim2.fromOffset(170, 60)
		gui.SizeOffset = Vector2.new(0, 0.5)
		gui.StudsOffsetWorldSpace = Vector3.new(0, anchor.Size.Y / 2 + 0.8, 0)
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		local button = Kit.button({
			Name = "Odds",
			Kind = "Purple",
			Text = "🎲 Odds",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 0, Theme.Size.ButtonHeight),
			Parent = gui,
		})
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = button
		button.Activated:Connect(openOdds)
		gui.Parent = playerGui
		infoGui = gui
		infoButton = button
		renderInfo()
	end

	--------------------------------------------------------------------------------------------------------------
	-- Rider cards
	--------------------------------------------------------------------------------------------------------------
	local hire: (rider: Rider) -> ()
	local refresh: () -> ()
	local bounceOn = not Kit.reducedMotion() -- the ride bounce; the card loop keeps it current

	local function buildCard(rider: Rider, root: BasePart)
		local nurse = rawget(data.Nurses, rider.NurseId)
		local info = rarityInfo(rider.Rarity)
		local color = rider.Color

		local gui = Instance.new("BillboardGui")
		gui.Name = "BeltCard_" .. rider.Id
		gui.Adornee = root
		gui.AlwaysOnTop = false -- a chip sits in the world; the full card is drawn on top (draw)
		gui.Active = true
		gui.ClipsDescendants = false -- the NEW! sticker pokes out of the card's corner
		gui.LightInfluence = 0
		gui.MaxDistance = CARD_MAX_DISTANCE
		gui.ResetOnSpawn = false
		gui.Enabled = false -- the card loop shows it once you're near (refresh)
		gui.Size = UDim2.fromScale(CHIP_STUDS.X, CHIP_STUDS.Y)
		gui.SizeOffset = Vector2.new(0, 0.5) -- the bottom edge sits on the anchor point, above the rider's head
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		local ok, cf, size = pcall(function()
			return rider.Model:GetBoundingBox()
		end)
		local above = if ok then (cf.Position.Y + size.Y / 2) - root.Position.Y + 0.5 else 3
		gui.StudsOffsetWorldSpace = Vector3.new(0, math.clamp(above, 1.5, 12), 0)

		-- The full card -------------------------------------------------------------------------------------
		local full = frame({ Name = "Full", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
		full.Parent = gui
		local halo: Frame? = nil
		if BeltLogic.shouts(rider.Rarity) then
			local glow = frame({
				Name = "Halo",
				BackgroundColor3 = color,
				BackgroundTransparency = 0.5,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 0,
				Parent = full,
			})
			Kit.corner(glow, Theme.Size.Corner + HALO)
			halo = glow
		end
		local card = frame({
			Name = "Card",
			BackgroundColor3 = Theme.Colors.Paper,
			Position = UDim2.fromOffset(HALO, HALO),
			Size = UDim2.new(1, -HALO * 2, 1, -HALO * 2),
			ZIndex = 1,
			Parent = full,
		})
		Kit.corner(card, Theme.Size.Corner)
		Kit.rarityFrame(card, rider.Rarity)
		local band = Kit.label({
			Name = "Band",
			Text = info.Icon .. " " .. info.Name,
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = Kit.lighten(color, 0.08),
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 2,
			Parent = card,
		})
		Kit.corner(band, Theme.Size.Corner)
		Palette.candyGradient(band)
		local bandPad = Instance.new("UIPadding")
		bandPad.PaddingTop = UDim.new(0, 4)
		bandPad.PaddingBottom = UDim.new(0, 4)
		bandPad.PaddingLeft = UDim.new(0, 30)
		bandPad.PaddingRight = UDim.new(0, 30)
		bandPad.Parent = band
		local sticker = Kit.label({
			Name = "New",
			Text = "NEW!",
			TextSize = Theme.TextSize.Small,
			TextWrapped = false,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(-8, -10),
			Size = UDim2.fromOffset(56, 24),
			Rotation = -10,
			Visible = false,
			ZIndex = 5,
			Parent = card,
		})
		Kit.corner(sticker, 12)
		Kit.stroke(sticker, Theme.Colors.Outline, 2.5)
		local name = Kit.label({
			Name = "NurseName",
			Text = if nurse then nurse.Name else "?",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 34),
			Size = UDim2.new(1, -12, 0, 24),
			ZIndex = 2,
			Parent = card,
		})
		textLimit(name, 22)
		local stat = Kit.label({
			Name = "Stat",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.new(1, -12, 0, 22),
			ZIndex = 2,
			Parent = card,
		})
		textLimit(stat, 18)
		local button = Kit.button({
			Name = "Hire",
			Kind = "Cash",
			Text = "Hire",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -14, 0, Theme.Size.ButtonHeight),
			ZIndex = 2,
			Parent = card,
		})
		local buttonPad = Instance.new("UIPadding")
		buttonPad.PaddingLeft = UDim.new(0, 8)
		buttonPad.PaddingRight = UDim.new(0, 8)
		buttonPad.PaddingTop = UDim.new(0, 10)
		buttonPad.PaddingBottom = UDim.new(0, 10)
		buttonPad.Parent = button
		-- The prompt's key (E / X) while the Hire prompt is up: a small dark keycap on the button's top-left corner.
		local key = Kit.label({
			Name = "Key",
			Text = "E",
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Outline,
			BackgroundTransparency = 0,
			Position = UDim2.new(0, 2, 1, -8 - Theme.Size.ButtonHeight - 10),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(key, 8)
		local pill = Kit.label({
			Name = "Done",
			Text = "",
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Good,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -14, 0, Theme.Size.ButtonHeight),
			Visible = false,
			ZIndex = 2,
			Parent = card,
		})
		Kit.corner(pill, Theme.Size.Corner)
		Kit.stroke(pill, Theme.Colors.Outline, Theme.Size.Stroke)
		local pillPad = Instance.new("UIPadding")
		pillPad.PaddingTop = UDim.new(0, 10)
		pillPad.PaddingBottom = UDim.new(0, 10)
		pillPad.Parent = pill
		button.Activated:Connect(function()
			hire(rider)
		end)

		-- The chip ------------------------------------------------------------------------------------------
		-- It fills the stud-sized canvas, so it shrinks with distance; never bigger than CHIP_SIZE px up close.
		local chipFrame = frame({
			Name = "Chip",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 1),
		})
		local chipMax = Instance.new("UISizeConstraint")
		chipMax.MaxSize = CHIP_SIZE
		chipMax.Parent = chipFrame
		local chipShape = Instance.new("UIAspectRatioConstraint")
		chipShape.AspectRatio = CHIP_SIZE.X / CHIP_SIZE.Y
		chipShape.Parent = chipFrame
		chipFrame.Parent = gui
		local chip = Instance.new("TextButton")
		chip.Name = "Tap"
		chip.Text = ""
		chip.AutoButtonColor = false
		chip.BackgroundColor3 = Theme.Colors.Paper
		chip.BorderSizePixel = 0
		chip.Position = UDim2.fromScale(0.035, 0.06)
		chip.Size = UDim2.fromScale(0.93, 0.88)
		Kit.corner(chip, Theme.Size.Corner)
		Kit.rarityFrame(chip, rider.Rarity)
		chip.Parent = chipFrame
		local chipIcon = Kit.label({
			Name = "Icon",
			Text = if nurse then nurse.Icon else "❔",
			TextScaled = true,
			Position = UDim2.fromScale(0.05, 0.1),
			Size = UDim2.fromScale(0.36, 0.8),
			ZIndex = 2,
			Parent = chip,
		})
		local chipPrice = Kit.label({
			Name = "Price",
			Text = "",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.95, 0.5),
			Size = UDim2.fromScale(0.54, 0.5),
			ZIndex = 2,
			Parent = chip,
		})
		textLimit(chipPrice, 24)
		local chipDot = frame({
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Theme.Colors.Dot,
			Visible = false,
			ZIndex = 3,
			Parent = chip,
		})
		Kit.corner(chipDot, 8)
		Kit.stroke(chipDot, Theme.Colors.Outline, 2)
		chip.Activated:Connect(function()
			tappedId = rider.Id
			Hud.sound("Pop")
			refresh()
		end)

		gui.Parent = playerGui
		rider.Gui = gui
		rider.Card = card
		rider.FullFrame = full
		rider.ChipFrame = chipFrame
		rider.Halo = halo
		rider.Band = band
		rider.Sticker = sticker
		rider.NameLabel = name
		rider.Stat = stat
		rider.Button = button
		rider.Key = key
		rider.Pill = pill
		rider.ChipIcon = chipIcon
		rider.ChipPrice = chipPrice
		rider.ChipDot = chipDot
	end

	-- A soft light and a few sparkles in the rarity's colour on Epic and up (client-only, never shadows). A model that
	-- already sparkles (NurseBuilder's RarityFX) keeps its own, and those are switched off here with reduced motion.
	local function addGlow(rider: Rider, root: BasePart)
		for _, descendant in rider.Model:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				table.insert(rider.Sparkles, descendant)
				descendant.Enabled = not Kit.reducedMotion()
			end
		end
		if not BeltLogic.shouts(rider.Rarity) then
			return
		end
		if not root:FindFirstChildWhichIsA("Light", true) then
			local light = Instance.new("PointLight")
			light.Name = "BeltGlow"
			light.Color = rider.Color
			light.Brightness = 1.6
			light.Range = 10
			light.Shadows = false
			light.Parent = root
			table.insert(rider.Added, light)
		end
		if #rider.Sparkles == 0 then
			local attachment = Instance.new("Attachment")
			attachment.Name = "BeltSparkles"
			attachment.Parent = root
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Name = "Sparkles"
			sparkles.Texture = SOFT_DOT
			sparkles.Color = ColorSequence.new(Kit.lighten(rider.Color, 0.25), rider.Color)
			sparkles.LightEmission = 1
			sparkles.LightInfluence = 0
			sparkles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkles.Transparency = NumberSequence.new(0.15, 1)
			sparkles.Lifetime = NumberRange.new(1.2, 1.8)
			sparkles.Speed = NumberRange.new(1, 2)
			sparkles.SpreadAngle = Vector2.new(180, 180)
			sparkles.Acceleration = Vector3.new(0, 1.2, 0)
			sparkles.Rate = 5
			sparkles.Enabled = not Kit.reducedMotion()
			sparkles.Parent = attachment
			table.insert(rider.Sparkles, sparkles)
			table.insert(rider.Added, attachment)
		end
	end

	local function setHalo(rider: Rider, calm: boolean)
		local halo = rider.Halo
		if not halo then
			return
		end
		local running = rider.HaloTween
		if calm or not rider.Full or not rider.Open then
			if running then
				running:Cancel()
				rider.HaloTween = nil
			end
			halo.BackgroundTransparency = 0.5
			return
		end
		if not running then
			halo.BackgroundTransparency = 0.45
			local pulse = TweenService:Create(
				halo,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.8 }
			)
			rider.HaloTween = pulse
			pulse:Play()
		end
	end

	local function draw(rider: Rider, calm: boolean)
		local state = ctx.State
		local entry = myEntry(rider.NurseId)
		local price = BeltLogic.price(cfg, rider.Rarity, myLevel())
		local hireState = Pure.hireState(rider.Hired, entry, cfg, state.Cash, price, rider.Distance)
		local full = rider.Id == focusId
		local mark = journalMark(rider.NurseId)
		local keyText = if rider.PromptShown and rider.Prompt then keyLabel(rider.Prompt :: ProximityPrompt) else nil
		rider.HireState = hireState
		rider.Price = price

		local prompt = rider.Prompt
		local priceText = "💰" .. Pure.short(price)
		if prompt and prompt.ObjectText ~= priceText then
			prompt.ObjectText = priceText
		end
		for _, sparkles in rider.Sparkles do
			if sparkles.Enabled == calm then
				sparkles.Enabled = not calm
			end
		end

		local key = table.concat({
			tostring(full),
			hireState,
			tostring(price),
			tostring(if type(entry) == "table" then entry.Level else 0),
			tostring(mark),
			tostring(keyText),
			tostring(calm),
			tostring(rider.Busy),
			tostring(rider.Open),
		}, "|")
		if key == rider.Drawn then
			return
		end
		rider.Drawn = key

		local gui = rider.Gui
		local fullFrame, chipFrame = rider.FullFrame, rider.ChipFrame
		if not gui or not fullFrame or not chipFrame then
			return
		end
		local wasFull = rider.Full
		rider.Full = full
		-- The full card: a fixed pixel size, drawn on top. A chip: studs (it shrinks with distance), in the world.
		gui.Size = if full
			then UDim2.fromOffset(FULL_SIZE.X, FULL_SIZE.Y)
			else UDim2.fromScale(CHIP_STUDS.X, CHIP_STUDS.Y)
		gui.AlwaysOnTop = full
		fullFrame.Visible = full
		chipFrame.Visible = not full
		if full and not wasFull then
			Kit.popIn(fullFrame)
		end
		setHalo(rider, calm)

		local hiredByMe = mark == "Hired"
		local sticker = rider.Sticker
		if sticker then
			sticker.Visible = not hiredByMe and hireState ~= "Hired"
		end
		local chipDot = rider.ChipDot
		if chipDot then
			chipDot.Visible = not hiredByMe and hireState ~= "Hired"
		end

		local stat = rider.Stat
		if stat then
			local level = if type(entry) == "table" and type(entry.Level) == "number" then entry.Level else 0
			local text = (Pure.ROLE_ICONS[rider.Role] or "") .. " " .. Pure.statText(rider.Role, rider.Rarity, 1, cfg)
			if level > 0 and hireState ~= "Max" then
				text ..= "  ⬆️Lv" .. (level + 1)
			end
			stat.Text = text
		end

		local button, pill, keyChip = rider.Button, rider.Pill, rider.Key
		if button and pill and keyChip then
			local done = hireState == "Hired" or hireState == "Max"
			button.Visible = not done
			pill.Visible = done
			keyChip.Visible = not done and keyText ~= nil
			keyChip.Text = keyText or ""
			if hireState == "Hired" then
				pill.Text = "✅ Hired"
				pill.BackgroundColor3 = Theme.Colors.Good
			elseif hireState == "Max" then
				pill.Text = "⭐ MAX"
				pill.BackgroundColor3 = Theme.Colors.Purple
			end
			if not done then
				button.Text = if rider.Busy then "⏳" else "Hire " .. priceText
				local ready = hireState == "Ready"
				local kitColor = button:GetAttribute("KitColor")
				button.BackgroundColor3 = if ready and typeof(kitColor) == "Color3"
					then kitColor
					else Theme.Colors.Disabled
				local border = borderOf(button)
				if border then
					border.Transparency = if ready then 0 else 0.3
				end
			end
		end

		local chipPrice = rider.ChipPrice
		if chipPrice then
			chipPrice.Text = if hireState == "Hired" then "✅" elseif hireState == "Max" then "⭐MAX" else priceText
			chipPrice.TextColor3 = if hireState == "Ready" or hireState == "Hired"
				then Theme.Colors.Ink
				else Theme.Colors.InkSoft
		end
	end

	hire = function(rider: Rider)
		if rider.Busy then
			return
		end
		local button = rider.Button
		local state = rider.HireState
		if state == "Far" then
			ctx.toast("Get closer! 👣") -- the server's own words (NurseBelt) for the same case
			Hud.shake(button)
			return
		elseif state == "Poor" then
			local short = rider.Price - (if type(ctx.State.Cash) == "number" then ctx.State.Cash else 0)
			ctx.toast("Need 💰" .. Hud.format(math.max(short, 1)) .. " more!")
			Hud.shake(button)
			return
		elseif state ~= "Ready" then
			return
		end
		rider.Busy = true
		rider.Drawn = ""
		draw(rider, Kit.reducedMotion())
		local ok, message = Hud.ask(ctx.Remotes.HireNurse, rider.Id)
		rider.Busy = false
		rider.Drawn = ""
		if ok then
			-- The "Hire" cue comes with the server's NurseNews (Feel/Sounds), the same for a prompt hire.
			if message ~= "" then
				ctx.toast(message)
			end
			local card = rider.Card
			if card then
				Kit.bump(card)
			end
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
			Hud.shake(button)
		end
		if riders[rider.Model] then
			draw(rider, Kit.reducedMotion())
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Movement (every frame) and the card loop (4 Hz)
	--------------------------------------------------------------------------------------------------------------
	local function formulaPosition(rider: Rider, now: number): (Vector3?, number)
		local a, b = beltStart, beltEnd
		if not a or not b then
			return nil, 1
		end
		local alpha = BeltLogic.alpha(rider.StartAt, now, rider.Ride)
		return a.Position:Lerp(b.Position, alpha), alpha
	end

	local function step()
		local now = Workspace:GetServerTimeNow()
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else nil
		local bounce = bounceOn
		for _, rider in riders do
			local root = rider.Root
			if root and rider.Free then
				local position, alpha = formulaPosition(rider, now)
				if position and alpha < 1 and (not eye or (position - eye).Magnitude <= MOVE_MAX_DISTANCE) then
					if bounce then
						local t = (now + rider.Phase) / BOUNCE_SECONDS
						position += Vector3.new(0, math.abs(math.sin(t * math.pi)) * BOUNCE_HEIGHT, 0)
					end
					root.CFrame = CFrame.new(position) * root.CFrame.Rotation
				end
			end
		end
	end

	-- Studs from a point to the belt (the segment BeltStart..BeltEnd); huge when there's no belt.
	local function beltDistance(point: Vector3): number
		local a, b = beltStart, beltEnd
		if not a or not b then
			return math.huge
		end
		local from, along = a.Position, b.Position - a.Position
		local t = math.clamp((point - from):Dot(along) / math.max(along:Dot(along), 1e-6), 0, 1)
		return (from + along * t - point).Magnitude
	end

	-- The frame loop runs only while there are riders and the camera is near enough for the glide to show.
	local function syncMoving()
		local camera = Workspace.CurrentCamera
		local near = next(riders) ~= nil and camera ~= nil and beltDistance(camera.CFrame.Position) <= MOVE_MAX_DISTANCE
		if near and not moveConnection then
			moveConnection = RunService.RenderStepped:Connect(step)
		elseif not near and moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
	end

	local hireReach = if type(cfg.Belt.HireDistance) == "number" then cfg.Belt.HireDistance else 40
	local chipReach = hireReach + CHIP_MARGIN

	refresh = function()
		local now = Workspace:GetServerTimeNow()
		local here = characterPosition(player)
		local calm = Kit.reducedMotion()
		bounceOn = not calm
		syncMoving()
		local candidates: { Candidate } = {}
		local prompted: number? = nil
		for model, rider in riders do
			rider.Free = not rider.Hired and not CollectionService:HasTag(model, "CreatureMotion")
			local position, alpha = formulaPosition(rider, now)
			rider.Open = not rider.Hired and alpha < 1
			rider.Distance = if here and position then (position - here).Magnitude else math.huge
			if rider.Gui then -- only a rider with a card can show it
				if rider.PromptShown then
					prompted = rider.Id
				end
				table.insert(candidates, { Id = rider.Id, Distance = rider.Distance, Open = rider.Open })
			end
		end
		if tappedId and not byId[tappedId] then
			tappedId = nil
		end
		focusId = Pure.focus(candidates, prompted, tappedId, focusId, FOCUS_REACH)
		for _, rider in riders do
			-- Only riders near you show anything: a far chip is clutter over everyone's clinic (and its rarity
			-- shimmer would run every frame; Kit skips hidden ones).
			local gui = rider.Gui
			if gui then
				local show = rider.Id == focusId or rider.Distance <= chipReach
				if gui.Enabled ~= show then
					gui.Enabled = show
				end
			end
			draw(rider, calm)
		end
	end

	local function ensureLoops()
		syncMoving()
		if looping then
			return
		end
		looping = true
		task.spawn(function()
			while next(riders) ~= nil do
				local ok, err = pcall(refresh)
				if not ok then
					warn("[BeltView] " .. tostring(err))
				end
				task.wait(REFRESH_SECONDS)
			end
			looping = false
		end)
	end

	local function removeRider(model: Instance)
		local rider = riders[model :: Model]
		if not rider then
			return
		end
		riders[model :: Model] = nil
		if byId[rider.Id] == rider then
			byId[rider.Id] = nil
		end
		for _, connection in rider.Connections do
			connection:Disconnect()
		end
		local pulse = rider.HaloTween
		if pulse then
			pulse:Cancel()
		end
		if rider.Gui then
			rider.Gui:Destroy()
		end
		for _, added in rider.Added do
			added:Destroy()
		end
		-- Its prompt keeps the Custom style: a hired nurse walking off never shows a default "Hire" prompt.
		if focusId == rider.Id then
			focusId = nil
		end
		if next(riders) == nil and moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
	end

	local function hookPrompt(rider: Rider, root: BasePart)
		local attachment = root:WaitForChild("HireAttachment", 10)
		local prompt = attachment and attachment:WaitForChild("HirePrompt", 10)
		if not prompt or not prompt:IsA("ProximityPrompt") or not riders[rider.Model] then
			return
		end
		rider.Prompt = prompt
		if rider.Gui then
			prompt.Style = Enum.ProximityPromptStyle.Custom -- the card is the prompt's look
		end
		table.insert(
			rider.Connections,
			prompt.PromptShown:Connect(function()
				rider.PromptShown = true
				rider.Drawn = ""
			end)
		)
		table.insert(
			rider.Connections,
			prompt.PromptHidden:Connect(function()
				rider.PromptShown = false
				rider.Drawn = ""
			end)
		)
		rider.Drawn = ""
	end

	local function addRider(model: Instance)
		if not model:IsA("Model") or riders[model] then
			return
		end
		-- The server sets the attributes before it parents a rider; give a late one a few seconds anyway.
		local riderId = model:GetAttribute("RiderId")
		local waited = 0
		while type(riderId) ~= "number" and waited < 5 and model.Parent do
			waited += task.wait(0.2)
			riderId = model:GetAttribute("RiderId")
		end
		if type(riderId) ~= "number" or not model.Parent or riders[model] then
			return
		end
		local nurseId = model:GetAttribute("NurseId")
		local nurse = if type(nurseId) == "string" then rawget(data.Nurses, nurseId) else nil
		local rarity = model:GetAttribute("Rarity")
		if type(rarity) ~= "string" or not rawget(data.Rarities, rarity) then
			rarity = if nurse then nurse.Rarity else "Common"
		end
		local role = model:GetAttribute("Role")
		if type(role) ~= "string" then
			role = if nurse then nurse.Role else "Maker"
		end
		local startAt = model:GetAttribute("StartAt")
		local ride = model:GetAttribute("RideSeconds")
		local rider: Rider = {
			Id = riderId :: number,
			Model = model,
			Root = nil,
			NurseId = if type(nurseId) == "string" then nurseId else "",
			Rarity = rarity :: string,
			Role = role :: string,
			Color = hexColor(rarityInfo(rarity :: string).Color, Theme.Colors.Quiet),
			StartAt = if type(startAt) == "number" then startAt else Workspace:GetServerTimeNow(),
			Ride = if type(ride) == "number" then ride else cfg.Belt.RideSeconds,
			Hired = model:GetAttribute("Hired") == true,
			Free = false,
			Open = true,
			Distance = math.huge,
			Phase = math.random() * BOUNCE_SECONDS,
			PromptShown = false,
			Prompt = nil,
			Busy = false,
			HireState = "Far",
			Price = 0,
			Drawn = "",
			Full = false,
			Sparkles = {},
			Added = {},
			Connections = {},
		}
		riders[model] = rider
		byId[rider.Id] = rider
		table.insert(
			rider.Connections,
			model.AttributeChanged:Connect(function(name: string)
				local value = model:GetAttribute(name)
				if name == "Hired" then
					rider.Hired = value == true
					if rider.Hired then
						rider.Free = false
						rider.Open = false
					end
				elseif name == "StartAt" and type(value) == "number" then
					rider.StartAt = value
				elseif name == "RideSeconds" and type(value) == "number" then
					rider.Ride = value
				end
				rider.Drawn = ""
			end)
		)

		local primary = model.PrimaryPart
		local root = primary or model:WaitForChild("Root", 10)
		if not root or not root:IsA("BasePart") or riders[model] ~= rider then
			return
		end
		rider.Root = root
		rider.Free = not rider.Hired
		if nurse then
			local built, err = pcall(buildCard, rider, root)
			if not built then
				warn("[BeltView] card for " .. rider.NurseId .. " failed: " .. tostring(err))
				if rider.Gui then
					rider.Gui:Destroy()
				end
				rider.Gui = nil
			end
		end
		pcall(addGlow, rider, root)
		ensureLoops()
		task.spawn(hookPrompt, rider, root)
	end

	-- The conveyor's stripes (NurseBelt's Conveyor > ConveyorGui > Clip > Stripes) scroll by one stripe and wrap, at
	-- the conveyor's StudsPerSecond: one repeating Linear tween, so no Lua runs per frame. Still with reduced motion.
	-- A kit belt without them is left as it is.
	local boundBelt: Instance? = nil
	local stripes: GuiObject? = nil
	local stripeTween: Tween? = nil
	local function syncStripes()
		if stripeTween then
			stripeTween:Cancel()
			stripeTween = nil
		end
		local surface = stripes
		if not surface then
			return
		end
		surface.Position = UDim2.fromScale(0, 0)
		local conveyor = surface:FindFirstAncestorWhichIsA("BasePart")
		if not conveyor or Kit.reducedMotion() then
			return
		end
		local stripeStuds = conveyor:GetAttribute("StripeStuds")
		local speed = conveyor:GetAttribute("StudsPerSecond")
		local length = conveyor.Size.X
		if
			type(stripeStuds) ~= "number"
			or type(speed) ~= "number"
			or stripeStuds <= 0
			or speed <= 0
			or length <= 0
		then
			return
		end
		stripeTween = TweenService:Create(
			surface,
			TweenInfo.new(stripeStuds / speed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Position = UDim2.fromScale(-stripeStuds / length, 0) }
		)
		stripeTween:Play()
	end
	local function stopStripes()
		stripes = nil
		syncStripes()
	end
	local function bindStripes(belt: Instance)
		local conveyor = belt:WaitForChild("Conveyor", 15)
		local gui = conveyor and conveyor:WaitForChild("ConveyorGui", 5)
		local clip = gui and gui:WaitForChild("Clip", 5)
		local found = clip and clip:WaitForChild("Stripes", 5)
		if boundBelt == belt and found and found:IsA("GuiObject") then
			stripes = found
			syncStripes()
		end
	end
	player:GetAttributeChangedSignal("ReduceEffects"):Connect(syncStripes)

	local function unbindBelt()
		for _, connection in beltConnections do
			connection:Disconnect()
		end
		table.clear(beltConnections)
		for model in table.clone(riders) do
			removeRider(model)
		end
		if infoGui then
			infoGui:Destroy()
			infoGui = nil
			infoButton = nil
		end
		beltStart, beltEnd = nil, nil
		stopStripes()
	end

	local function bindBelt(belt: Instance)
		if boundBelt == belt then
			return
		end
		unbindBelt()
		boundBelt = belt
		local start = belt:WaitForChild("BeltStart", 15)
		local finish = belt:WaitForChild("BeltEnd", 15)
		local folder = belt:WaitForChild("Riders", 15)
		if boundBelt ~= belt then
			return
		end
		if not (start and start:IsA("BasePart") and finish and finish:IsA("BasePart") and folder) then
			warn("[BeltView] Workspace.NurseBelt has no BeltStart / BeltEnd / Riders")
			return
		end
		beltStart, beltEnd = start, finish
		buildInfo(belt)
		task.spawn(bindStripes, belt)
		table.insert(
			beltConnections,
			folder.ChildAdded:Connect(function(child)
				task.spawn(addRider, child)
			end)
		)
		table.insert(beltConnections, folder.ChildRemoved:Connect(removeRider))
		table.insert(
			beltConnections,
			belt.AncestryChanged:Connect(function()
				if not belt:IsDescendantOf(Workspace) and boundBelt == belt then
					boundBelt = nil
					unbindBelt()
				end
			end)
		)
		for _, child in folder:GetChildren() do
			task.spawn(addRider, child)
		end
	end

	local function tryBind(child: Instance)
		if child.Name == "NurseBelt" and child:IsA("Model") then
			task.spawn(bindBelt, child)
		end
	end
	Workspace.ChildAdded:Connect(tryBind)
	local existing = Workspace:FindFirstChild("NurseBelt")
	if existing then
		tryBind(existing)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Banners
	--------------------------------------------------------------------------------------------------------------
	local goldColor = hexColor(rarityInfo("Secret").Color, Theme.Colors.Cash)
	local goldenShown = false
	local nightShown = false

	local function allowed(): boolean
		return not Pure.quiet(ctx.State.Tutorial)
	end

	-- Once per window, for a few seconds, with the real chance (no countdown, no "limited time": red line 3).
	local function syncGolden(on: boolean)
		if on and allowed() then
			if not goldenShown then
				goldenShown = true
				Hud.sound("Golden")
				local secret = BeltLogic.odds(cfg, nightRush(), true).Secret
				ctx.fire("Banner", {
					Id = "GoldenHour",
					Icon = "👑",
					Text = "Golden Hour: Secret " .. Pure.percent(secret),
					Color = goldColor,
					Seconds = GOLDEN_BANNER_SECONDS,
				})
			end
		elseif not on and goldenShown then
			goldenShown = false
			ctx.fire("Banner", { Id = "GoldenHour", Icon = "👑", Text = "", Seconds = 0 })
		end
		renderInfo()
		renderOdds()
	end

	local function syncNight()
		local on = nightRush()
		if not on then
			if nightShown then
				ctx.fire("Banner", { Id = "NightRush", Icon = "🌙", Text = "", Seconds = 0 })
			end
			nightShown = false
		elseif not nightShown and allowed() then
			nightShown = true
			ctx.fire("Banner", {
				Id = "NightRush",
				Icon = "🌙",
				Text = "Night Rush: more rare nurses!",
				Color = Theme.Colors.Night,
				Seconds = NIGHT_BANNER_SECONDS,
			})
		end
		renderInfo()
		renderOdds()
	end

	local function syncGoldenFromAttributes()
		syncGolden(goldenHour())
	end

	Workspace:GetAttributeChangedSignal("GoldenHour"):Connect(syncGoldenFromAttributes)
	Workspace:GetAttributeChangedSignal("NightRush"):Connect(syncNight)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(syncNight)
	Workspace:GetAttributeChangedSignal("BeltPity"):Connect(renderOdds)

	ctx.on("Shout", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.Kind == "Golden" then
			if info.On == true then
				syncGolden(true)
			elseif info.On == false then
				syncGolden(false)
			end
		elseif info.Kind == "Arrival" then
			local rarity = if type(info.Rarity) == "string" then rawget(data.Rarities, info.Rarity) else nil
			if rarity and BeltLogic.shouts(info.Rarity) and allowed() then
				ctx.fire("Banner", {
					Id = "BeltArrival",
					Icon = rarity.Icon,
					Text = rarity.Name .. " nurse arrived!",
					Color = hexColor(rarity.Color, Theme.Colors.Purple),
					Seconds = ARRIVAL_BANNER_SECONDS,
				})
				Hud.sound("Arrival")
			end
			local rider = if type(info.RiderId) == "number" then byId[info.RiderId] else nil
			if rider and rider.Gui and not Kit.reducedMotion() then
				Hud.pop(if rider.Full then rider.FullFrame else rider.ChipFrame, 1.25)
			end
		elseif info.Kind == "Hired" then
			local nurse = if type(info.NurseId) == "string" then rawget(data.Nurses, info.NurseId) else nil
			local by = if type(info.By) == "string" then info.By else ""
			if nurse and by ~= "" and by ~= player.DisplayName and allowed() then
				ctx.fire("Banner", {
					Id = "BeltHired",
					Icon = "🎉",
					Text = by .. " hired " .. nurse.Name .. "!",
					Color = hexColor(rarityInfo(nurse.Rarity).Color, Theme.Colors.Purple),
					Seconds = HIRED_BANNER_SECONDS,
				})
			end
		end
	end)

	ctx.on("Open", function(name: any)
		if name == "NurseOdds" then
			openOdds()
		end
	end)

	-- Prices, NEW! stickers and ⬆️ follow your level, cash and journal; banners held back by the tutorial show
	-- once it ends.
	local wasAllowed = allowed()
	ctx.onState(function()
		for _, rider in riders do
			rider.Drawn = ""
		end
		renderOdds()
		local now = allowed()
		if now and not wasAllowed then
			syncGoldenFromAttributes()
			syncNight()
		end
		wasAllowed = now
	end)

	syncGoldenFromAttributes()
	syncNight()
end

return BeltView
