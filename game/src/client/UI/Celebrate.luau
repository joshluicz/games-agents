--!strict
-- Big celebration screens (depth-update design §4, build plan §B9). OWNER: T6; Progression v2: T8; look overhaul: T8.
--   init(ctx)   listens for the bus "Celebrate" (info: Types.CelebrateInfo): from the server for a level-up
--               ("LevelUp"), a first-time hire ("NewNurse") and a completed Journal group ("JournalSet"); Feel/CureFX
--               fires "Room" for a room you just got (with an extra field `Room = <RoomId>`, see Words.of)
-- Progression v2 (build plan §C T8): "Rebirth" (Count, Theme): "🏢 New branch!" in the new theme's colours (the
-- ribbon its roof, the bubble its walls, the rays its roof), the count on the bubble ("🏢 2"), chips for what the
-- branch gave (💰⭐ ×1.25, 🌳 +3, 👩‍⚕️ +1 nurse slot) and every "Unlock" the server sends right after it, folded in as
-- chips (Golden patients with their odds, "🎲 1 in 50"). Its button is "🃏 Pick a card!": it closes and opens the
-- Branch panel's perk cards (bus Open("Branch", "Perks")); closing it any other way just closes (the 🛒 dot waits,
-- no nagging). As it closes, the branch's 🌳 points fly into 🛒. "Perk" (Perk): the card's icon, name and words.
-- "NurseLevel" (NurseId, Level, Ability): the nurse's face, "⬆️ Lv 5", and its trick getting stronger. An "Unlock"
-- with no Rebirth to join shows on its own. A new nurse also shows its trick (its Data/Abilities chip).
-- What it shows: the screen dims, candy confetti rains, and in the middle the reward sits in a big white bubble on
-- turning rays (Kit.celebrate) under a big outlined title on a ribbon in the moment's colour: the new level's name
-- and its unlock chips (Data/Levels), the nurse's face with its rarity frame (Kit.rarityFrame, still) and its
-- rarity and role chips, a Journal group's 💰 and decor reward, or the room's name. A Collect "🎉 Yay!" button shines
-- (Kit.shine) and closes it; so does a tap anywhere after a moment, ButtonB, or Theme.Juice.CelebrateSeconds
-- passing (no countdown: it just gets out of the way). On closing, a Journal group's cash flies into 💰 and a new
-- nurse's icon into the 👩‍⚕️ button. One at a time (a short queue), never while the first-session tutorial runs
-- (it waits for the tutorial to end; the tutorial's own finale is the one exception). A treat card stays playable: one nobody tapped for (Words.PASSIVE: NurseLevel,
-- a lone Unlock) waits for an open card to close, and a card opening (bus TreatStart) closes whatever is up.
-- Calm (Kit.reducedMotion()): the rays hold still, no confetti, no bounce.
-- Sounds (Feel/Sounds over the bus): LevelUp, Celebrate (nurses, Journal sets, unlocks), Fanfare (rooms and the
-- tutorial's finale), and Progression v2's Rebirth, Perk and LevelNurse.
-- Display only: the server already granted whatever this shows.
--
-- Look overhaul (look build plan §B9, §D T8; memory-20261117-001):
--   · Kind "Tutorial": the tutorial's finale, fired on the client by UI/Tutorial and shown EVEN WHILE the tutorial
--     still runs (it jumps the queue; everything else still waits for the tutorial to end). "🎉 YOU DID IT!" with the
--     guide nurse's face in the bubble (Data/Guide.Look), its Chips ("📖 Collect them all", "🎯 Daily goals",
--     "👩‍⚕️ Hire nurses") and ONE "COMING UP" chip for info.Next (a FREE event only: Logic/NextEvent picked it; minutes,
--     never seconds, and it never ticks: memory-20261116-022).
--   · Restyled on the tokens: flat fills (no candy gradients or gloss), Theme.Radius.Large and Theme.Stroke.Bold, the
--     title at Theme.TextSize.Hero, text never under 18 (Kit.textLimit), and ONE perpetual effect: the shine on its
--     Collect "🎉 Yay!" (no breathing).
--   · Rebirth: the ribbon and the rays in the new theme's Roof colour and the bubble's ring in its Trim; the bubble
--     stays white (the walls stay the plot colour: themes no longer recolour walls, §G4).
--   · Fires the bus event "CelebrateClosed" (kind) as a screen closes (UI/Tutorial rings 📖 after the finale).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local NextEvent = require(Shared:WaitForChild("Logic"):WaitForChild("NextEvent"))
local RebirthLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Rebirth"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local MiniGames = require(script.Parent.MiniGames)
local Theme = require(script.Parent.Theme)

------------------------------------------------------------------------------------------------------------------
-- Words: what a celebration says, from its info and the Data tables. Pure (no Roblox APIs): a scratch Lune harness
-- loads the block between the markers on its own, so keep it self-contained.
------------------------------------------------------------------------------------------------------------------
-- BEGIN PURE
local Words = {}

export type CelebrateWords = {
	Kind: string,
	Title: string, -- ≤ 3 words
	Icon: string,
	Sub: string, -- one line under the title ("" = none)
	Chips: { string }, -- small chips (an emoji and a few words), at most MaxChips
	MaxChips: number,
	Rarity: string?, -- a nurse's or a Journal group's rarity (its colour and frame)
	NurseId: string?, -- a nurse to draw
	Cash: number?, -- a Journal group's cash (flies into 💰 on closing)
	Sound: string, -- the Feel/Sounds cue
	-- Progression v2
	Sticker: string?, -- the bubble's corner sticker ("🏢 2", "⬆️"); nil = the usual (NEW!, the rarity's icon)
	Colors: { string }?, -- Rebirth: the branch theme's Wall, Roof and Trim (hex), for the ribbon, bubble and rays
	Action: string?, -- "Perks": the button says "🃏 Pick a card!" and opens the Branch panel's perk cards
	Points: number?, -- Rebirth: tree points that fly into 🛒 as it closes
	-- Look overhaul
	Portrait: string?, -- "Guide": the tutorial's guide nurse's face in the bubble (Data/Guide.Look)
	Next: string?, -- Tutorial: the one "COMING UP" chip's words ("🌟 Golden Hour in 12m"); a FREE event only
}

local KINDS = {
	LevelUp = "LevelUp",
	NewNurse = "Celebrate",
	JournalSet = "Celebrate",
	Room = "Fanfare",
	-- Progression v2 (build plan §B3 CelebrateInfo kinds)
	Rebirth = "Rebirth",
	Perk = "Perk",
	NurseLevel = "LevelNurse",
	Unlock = "Celebrate",
	-- Look overhaul (T8)
	Tutorial = "Fanfare",
}
Words.KINDS = KINDS
-- Kinds that show even while the first-session tutorial runs (everything else waits for it to end).
Words.DURING_TUTORIAL = { Tutorial = true } :: { [string]: boolean }
-- Kinds nobody tapped for just now (a nurse levelling from cures, an unlock on its own): they wait for an open treat
-- card to close before they show (UI/Celebrate's queue).
Words.PASSIVE = { NurseLevel = true, Unlock = true } :: { [string]: boolean }
-- The same role icons as the belt and the Journal (UI/BeltView Pure.ROLE_ICONS; tests/Juice checks they match). Never
-- an item's icon (🧪 Potion, 🩹 Plaster): a pre-reader would read a Healer as a plaster.
local ROLE_ICONS = { Maker = "🛠️", Healer = "🩺", Cheerer = "🎉" }
Words.ROLE_ICONS = ROLE_ICONS
local MAX_CHIPS = 4
Words.MAX_CHIPS = MAX_CHIPS
-- A rebirth has more to say: what it gave (💰⭐, 🌳, a nurse slot) plus the unlocks folded into it.
Words.REBIRTH_CHIPS = 6
local MAX_TITLE_WORDS = 3

function Words.commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

-- A multiplier as kids read it: 1.25 -> "1.25", 1.5 -> "1.5", 2 -> "2".
function Words.decimal(n: number): string
	local text = string.format("%.2f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function cutWords(text: string, max: number): string
	local words = {}
	for word in string.gmatch(text, "%S+") do
		if #words >= max then
			break
		end
		table.insert(words, word)
	end
	return table.concat(words, " ")
end

local function finite(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- A whole number >= 0 (junk = 0).
local function whole(value: any): number
	local n = finite(value)
	return if n and n > 0 then math.floor(n) else 0
end

-- A row of a keyed Data map by id (rawget, so a map's .Order is never an id).
local function entry(map: any, id: any): any
	if type(map) ~= "table" or type(id) ~= "string" or id == "" then
		return nil
	end
	local found = rawget(map, id)
	return if type(found) == "table" then found else nil
end

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- The perk card for an id: one of the 12, or the Fallback (Data/Perks.FallbackId, "TreePoints").
local function perkOf(perks: any, id: any): any
	local found = entry(perks, id)
	if found then
		return found
	end
	if type(perks) == "table" and id ~= nil and id == perks.FallbackId and type(perks.Fallback) == "table" then
		return perks.Fallback
	end
	return nil
end

-- The roster cap after `count` rebirths (Config.Roster: Base + PerRebirth each, at most Max).
local function rosterCap(cfg: any, count: number): number
	local roster = if type(cfg) == "table" and type(cfg.Roster) == "table" then cfg.Roster else {}
	local base, per = whole(roster.Base), whole(roster.PerRebirth)
	local max = finite(roster.Max) or math.huge
	return math.min(base + per * count, max)
end

-- The chips one unlock adds (Logic/Rebirth.UNLOCKS rows): its icon and words, and for Golden patients their odds
-- ("🎲 1 in 50", from Config.GoldenChance), so the R3 unlock shows them (red line 3: odds always shown).
function Words.unlockChips(unlockId: any, data: any): { string }
	local row = entry(data.Unlocks, unlockId)
	if not row then
		return {}
	end
	local chips = { tostring(row.Icon) .. " " .. tostring(row.Text) }
	if unlockId == "Golden" then
		local cfg = data.Config
		local chance = if type(cfg) == "table" then finite(cfg.GoldenChance) else nil
		if chance and chance > 0 and chance <= 1 then
			table.insert(chips, "🎲 1 in " .. math.floor(1 / chance + 0.5))
		end
	end
	return chips
end

-- Folds an Unlock into a Rebirth celebration (the server sends them right after it): its chips join the Rebirth's,
-- up to its MaxChips. True when it was folded (the caller then shows no screen of its own).
function Words.fold(words: CelebrateWords, unlockId: any, data: any): boolean
	if words.Kind ~= "Rebirth" then
		return false
	end
	local chips = Words.unlockChips(unlockId, data)
	if #chips == 0 then
		return false
	end
	for _, text in chips do
		if #words.Chips < words.MaxChips then
			table.insert(words.Chips, text)
		end
	end
	return true
end

-- The tutorial finale's "COMING UP" chip: "🌟 Golden Hour in 12m" (label = Logic/NextEvent.label: minutes only).
-- nil for junk, an event already started, or no label function.
function Words.nextChip(next: any, now: any, label: any): string?
	if type(next) ~= "table" or type(label) ~= "function" then
		return nil
	end
	local at, clock = finite(next.At), finite(now)
	if not (at and clock) or at <= clock then
		return nil
	end
	if type(next.Icon) ~= "string" or type(next.Name) ~= "string" or next.Name == "" then
		return nil
	end
	return next.Icon .. " " .. next.Name .. " " .. tostring(label(at - clock))
end

-- What to show for a CelebrateInfo; nil for junk (no table, an unknown Kind, no Title or Icon).
-- data = { Nurses, Rarities, Levels, Decor, Rooms } (ctx.Data), and for Progression v2 also Perks, Themes,
-- Abilities, Unlocks (Logic/Rebirth.UNLOCKS) and Config (Rebirth, Roster, GoldenChance); for the look overhaul's
-- "Tutorial" kind NextLabel (Logic/NextEvent.label), with `now` on the same clock as info.Next.At.
function Words.of(info: any, data: any, now: number?): CelebrateWords?
	if type(info) ~= "table" or type(info.Kind) ~= "string" or KINDS[info.Kind] == nil then
		return nil
	end
	if type(info.Title) ~= "string" or info.Title == "" or type(info.Icon) ~= "string" then
		return nil
	end
	local words: CelebrateWords = {
		Kind = info.Kind,
		Title = cutWords(info.Title, MAX_TITLE_WORDS),
		Icon = info.Icon,
		Sub = "",
		Chips = {},
		MaxChips = if info.Kind == "Rebirth" then Words.REBIRTH_CHIPS else MAX_CHIPS,
		Rarity = nil,
		NurseId = nil,
		Cash = nil,
		Sound = KINDS[info.Kind],
		Sticker = nil,
		Colors = nil,
		Action = nil,
		Points = nil,
		Portrait = nil,
		Next = nil,
	}
	local function chip(text: string?)
		if text and text ~= "" and #words.Chips < words.MaxChips then
			table.insert(words.Chips, text)
		end
	end
	local function rarityOf(id: any): string?
		return if entry(data.Rarities, id) then id else nil
	end
	local function abilityChip(nurse: any)
		local ability = if nurse then entry(data.Abilities, nurse.Ability) else nil
		if ability then
			chip(tostring(ability.Icon) .. " " .. tostring(ability.Name))
		end
		return ability
	end

	if info.Kind == "LevelUp" then
		local level = info.Level
		local levels = data.Levels
		local row = if type(level) == "number"
				and level == math.floor(level)
				and type(levels) == "table"
			then levels[level]
			else nil
		if type(row) == "table" then
			words.Sub = "Lv " .. level .. " · " .. tostring(row.Name)
			if type(row.Unlocks) == "table" then
				for _, unlock in row.Unlocks do
					chip(if type(unlock) == "string" then unlock else nil)
				end
			end
		end
	elseif info.Kind == "NewNurse" then
		local nurse = entry(data.Nurses, info.NurseId)
		if nurse then
			words.NurseId = info.NurseId
			words.Rarity = rarityOf(nurse.Rarity)
			words.Sub = tostring(nurse.Name)
			local rarity = entry(data.Rarities, nurse.Rarity)
			if rarity then
				chip(rarity.Icon .. " " .. nurse.Rarity)
			end
			local roleIcon = ROLE_ICONS[nurse.Role]
			if roleIcon then
				chip(roleIcon .. " " .. nurse.Role)
			end
			abilityChip(nurse) -- Progression v2: its signature trick
		else
			words.Rarity = rarityOf(info.Rarity)
		end
		if type(info.Level) == "number" and info.Level > 1 then
			chip("⬆️ Lv " .. math.floor(info.Level))
		end
	elseif info.Kind == "JournalSet" then
		words.Rarity = rarityOf(info.Rarity)
		local rarity = entry(data.Rarities, info.Rarity)
		if rarity then
			words.Sub = rarity.Icon .. " " .. info.Rarity .. " nurses"
		end
		if type(info.Cash) == "number" and info.Cash > 0 then
			words.Cash = math.floor(info.Cash)
			chip("💰 " .. Words.commas(info.Cash))
		end
		local decor = entry(data.Decor, info.Decor)
		if decor then
			chip(tostring(decor.Icon) .. " " .. tostring(decor.Name))
		end
	elseif info.Kind == "Room" then
		local room = entry(data.Rooms, info.Room)
		if room then
			words.Sub = tostring(room.Name)
		end
	elseif info.Kind == "Rebirth" then
		-- "🏢 New branch!": the count on the bubble, the new theme's look and colours, what this branch gave you,
		-- and then a perk card to pick (every rebirth offers one: the 🌳 fallback when all 12 are owned).
		local count = whole(info.Count)
		if count > 0 then
			words.Sticker = "🏢 " .. count
		end
		local theme = entry(data.Themes, info.Theme)
		if theme then
			words.Sub = tostring(theme.Icon) .. " " .. tostring(theme.Name)
			if isHex(theme.Wall) and isHex(theme.Roof) and isHex(theme.Trim) then
				words.Colors = { theme.Wall, theme.Roof, theme.Trim }
			end
		end
		local cfg = if type(data.Config) == "table" then data.Config else {}
		local rebirth = if type(cfg.Rebirth) == "table" then cfg.Rebirth else nil
		if count > 0 and rebirth then
			local counted = math.min(count, finite(rebirth.MaxBonusRebirths) or count)
			local multiplier = 1 + math.max(0, finite(rebirth.CashPerRebirth) or 0) * counted
			if multiplier > 1 then
				chip("💰⭐ ×" .. Words.decimal(multiplier))
			end
			local points = whole(rebirth.PointsPerRebirth)
			if points > 0 then
				words.Points = points
				chip("🌳 +" .. points)
			end
			if rosterCap(cfg, count) > rosterCap(cfg, count - 1) then
				chip("👩‍⚕️ +1 nurse slot")
			end
		end
		words.Action = "Perks"
	elseif info.Kind == "Perk" then
		local perk = perkOf(data.Perks, info.Perk)
		if perk then
			words.Sub = tostring(perk.Name)
			chip(tostring(perk.Icon) .. " " .. tostring(perk.Text))
		end
	elseif info.Kind == "NurseLevel" then
		local nurse = entry(data.Nurses, info.NurseId)
		if nurse then
			words.NurseId = info.NurseId
			words.Rarity = rarityOf(nurse.Rarity)
			words.Sub = tostring(nurse.Name)
		end
		local level = whole(info.Level)
		if level > 0 then
			words.Sticker = "⬆️ " .. level
			chip("⬆️ Lv " .. level)
		end
		if info.Ability == true then
			local ability = abilityChip(nurse)
			if ability then
				chip("💪 Stronger trick")
				if ability.Daily ~= true then
					chip("🔁 Ready sooner")
				end
			end
		end
	elseif info.Kind == "Tutorial" then
		-- The finale: the guide nurse's face, what's next to do, and one free event coming up.
		words.Portrait = "Guide"
		if type(info.Chips) == "table" then
			for _, text in info.Chips do
				if type(text) == "string" and #words.Chips < words.MaxChips - 1 then
					chip(text)
				end
			end
		end
		words.Next = Words.nextChip(info.Next, now, data.NextLabel)
	elseif info.Kind == "Unlock" then
		local chips = Words.unlockChips(info.Unlock, data)
		local row = entry(data.Unlocks, info.Unlock)
		if row then
			words.Sub = tostring(row.Text)
		end
		for _, text in chips do
			chip(text)
		end
	end
	return words
end
-- END PURE

local Celebrate = {}
Celebrate.Words = Words

local MAX_QUEUE = 4
local TAP_GUARD = 0.7 -- seconds before a tap on the dim closes it (so the tap that caused it can't)
local BUBBLE = 150
local DIM = 0.35
local CLOSE_ACTION = "ClinicCloseCelebrate"

local ACCENTS: { [string]: Color3 } = {
	LevelUp = Theme.Colors.Primary,
	NewNurse = Theme.Colors.Cyan,
	JournalSet = Theme.Colors.Purple,
	Room = Theme.Colors.Good,
	Rebirth = Theme.Colors.Purple, -- the Candy theme (no colours of its own)
	Perk = Theme.Colors.Pink,
	NurseLevel = Theme.Colors.Cyan,
	Unlock = Theme.Colors.Good,
	Tutorial = Theme.Colors.Primary,
}
local EXTRA_SECONDS = { Rebirth = 3 } -- a rebirth has more to read before it closes by itself

local function fromHex(value: string?, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function textWidth(text: string): number
	return utf8.len(text) or #text
end

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

function Celebrate.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	-- What Words.of reads: the Data tables, plus the rebirth unlocks and the Config numbers it shows.
	local wordsData = {
		Nurses = data.Nurses,
		Rarities = data.Rarities,
		Levels = data.Levels,
		Decor = data.Decor,
		Rooms = data.Rooms,
		Perks = data.Perks,
		Themes = data.Themes,
		Abilities = data.Abilities,
		Unlocks = RebirthLogic.UNLOCKS,
		Config = ctx.Config,
		Guide = data.Guide,
		NextLabel = NextEvent.label,
	}
	local gui = Kit.screen("Celebrate", Theme.DisplayOrder.Celebrate)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.BackgroundColor3 = Theme.Colors.Shade
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Position = UDim2.fromOffset(-400, -400)
	dim.Size = UDim2.new(1, 800, 1, 800)
	dim.Parent = gui

	-- Confetti rains across the whole screen (above the dim, below the card).
	local rain = Instance.new("Frame")
	rain.Name = "Rain"
	rain.BackgroundTransparency = 1
	rain.Size = UDim2.fromScale(1, 1)
	rain.Parent = gui

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(0.94, 0.94)
	stage.BackgroundTransparency = 1
	stage.Visible = false
	local stageLimit = Instance.new("UISizeConstraint")
	stageLimit.MaxSize = Vector2.new(520, 580)
	stageLimit.Parent = stage
	stage.Parent = gui

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.fromScale(0.5, 0)
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = stage
	local list = Kit.list(content, Enum.FillDirection.Vertical, 10)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(content, stage)

	-- The reward: a white bubble (with an outer ring for a rarity frame) on rays and confetti.
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.LayoutOrder = 1
	burst.Size = UDim2.new(1, 0, 0, BUBBLE + 70)
	burst.Parent = content
	local core = Instance.new("Frame") -- a square in the middle, so the rays stay round
	core.Name = "Core"
	core.BackgroundTransparency = 1
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromOffset(BUBBLE + 40, BUBBLE + 40)
	core.ZIndex = 1
	core.Parent = burst
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(BUBBLE + 12, BUBBLE + 12)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	local ringRound = Instance.new("UICorner")
	ringRound.CornerRadius = Theme.Radius.Round
	ringRound.Parent = ring
	ring.Parent = core
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
	bubble.BackgroundColor3 = Theme.Colors.Paper
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	local bubbleRound = Instance.new("UICorner")
	bubbleRound.CornerRadius = Theme.Radius.Round
	bubbleRound.Parent = bubble
	Kit.stroke(bubble, Theme.Colors.Stroke, Theme.Stroke.Bold)
	bubble.Parent = core
	local face = Instance.new("Frame") -- the icon or the nurse's portrait
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.82, 0.82)
	face.BackgroundTransparency = 1
	face.ZIndex = 3
	face.Parent = bubble
	local sticker = Kit.label({ -- the rarity's icon on the bubble's corner, or "NEW!"
		Name = "Sticker",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Dot,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.12),
		Size = UDim2.fromOffset(74, 34),
		Rotation = 10,
		Visible = false,
		ZIndex = 4,
		Parent = bubble,
	})
	Kit.corner(sticker, Theme.Radius.Medium)
	Kit.stroke(sticker, Theme.Colors.Stroke, Theme.Stroke.Text)
	Kit.pad(sticker, Theme.Space.Step[1])
	Kit.textLimit(sticker, Theme.TextSize.Body) -- never under 18

	-- The title on a flat ribbon in the moment's colour.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.LayoutOrder = 2
	ribbon.Size = UDim2.new(0.92, 0, 0, 72)
	ribbon.BorderSizePixel = 0
	Kit.corner(ribbon, Theme.Radius.Large)
	Kit.stroke(ribbon, Theme.Colors.Stroke, Theme.Stroke.Bold)
	ribbon.Parent = content
	local title = Kit.label({
		Name = "Title",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 56),
		ZIndex = 2,
		Parent = ribbon,
	})
	Kit.textLimit(title, Theme.TextSize.Hero)
	Kit.outline(title, Theme.Stroke.Title)

	local sub = Kit.label({
		Name = "Sub",
		Text = "",
		Outlined = true,
		Font = Theme.Font,
		TextScaled = true,
		TextWrapped = false,
		LayoutOrder = 3,
		Size = UDim2.new(0.92, 0, 0, 36),
		Parent = content,
	})
	Kit.textLimit(sub, Theme.TextSize.Title)
	Kit.outline(sub, Theme.Stroke.Text)

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.LayoutOrder = 4
	chips.Size = UDim2.fromScale(0.96, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.Parent = content
	local chipList = Kit.list(chips, Enum.FillDirection.Horizontal, 8)
	chipList.Wraps = true
	chipList.VerticalAlignment = Enum.VerticalAlignment.Top
	local chipPad = Instance.new("UIPadding") -- room for the chips' outlines
	chipPad.PaddingTop = UDim.new(0, 3)
	chipPad.PaddingBottom = UDim.new(0, 3)
	chipPad.Parent = chips

	-- The tutorial finale's one "COMING UP" chip (a free event, in minutes; it never ticks).
	local comingUp = Instance.new("Frame")
	comingUp.Name = "ComingUp"
	comingUp.LayoutOrder = 5
	comingUp.AutomaticSize = Enum.AutomaticSize.X
	comingUp.Size = UDim2.fromOffset(0, 48)
	comingUp.BackgroundColor3 = Theme.Colors.Header
	comingUp.BorderSizePixel = 0
	comingUp.Visible = false
	Kit.corner(comingUp, Theme.Radius.Medium)
	Kit.stroke(comingUp, Theme.Colors.Stroke, Theme.Stroke.Bold)
	local comingPad = Kit.pad(comingUp, Theme.Space.PadCard)
	comingPad.PaddingTop = UDim.new(0, 0)
	comingPad.PaddingBottom = UDim.new(0, 0)
	local comingList = Kit.list(comingUp, Enum.FillDirection.Horizontal, Theme.Space.Gap)
	comingList.VerticalAlignment = Enum.VerticalAlignment.Center
	comingUp.Parent = content
	Kit.label({
		Name = "Caption",
		Text = "COMING UP",
		Outlined = true,
		TextColor3 = Theme.Colors.Cash,
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		LayoutOrder = 1,
		Parent = comingUp,
	})
	local comingText = Kit.label({
		Name = "Event",
		Text = "",
		TextColor3 = Theme.Colors.OnColor,
		TextSize = Theme.TextSize.Body,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		LayoutOrder = 2,
		Parent = comingUp,
	})

	local yay = Kit.button({
		Name = "Yay",
		Kind = "Collect",
		Text = "🎉 Yay!",
		TextSize = Theme.TextSize.Title,
		LayoutOrder = 6,
		Size = UDim2.fromOffset(220, 64),
		Parent = content,
	})
	Kit.shine(yay) -- the one perpetual effect (Theme.Motion.Perpetual): a Collect button may shine

	--------------------------------------------------------------------------------------------------------------
	-- Showing one
	--------------------------------------------------------------------------------------------------------------
	local queue: { CelebrateWords } = {}
	local showing = false
	local current: CelebrateWords? = nil
	local token = 0
	local openedAt = 0
	local stopFx: { () -> () } = {}
	local closeNow: (byButton: boolean?) -> () = function(_byButton: boolean?) end

	local function clearFx()
		for _, stop in stopFx do
			stop()
		end
		table.clear(stopFx)
	end

	local function makeChip(text: string, order: number): TextLabel
		local label = Kit.label({
			Name = "Chip",
			Text = text,
			TextScaled = true,
			TextWrapped = false,
			LayoutOrder = order,
			BackgroundColor3 = Theme.Colors.Paper,
			BackgroundTransparency = 0,
			-- Wider for longer words (a perk's line), so the text never shrinks past reading.
			Size = UDim2.fromOffset(math.clamp(textWidth(text) * 12 + 40, 190, 300), 40),
			Parent = chips,
		})
		Kit.textLimit(label, Theme.TextSize.Body)
		Kit.corner(label, Theme.Radius.Large)
		Kit.stroke(label, Theme.Colors.Stroke, Theme.Stroke.Fine)
		local pad = Kit.pad(label, Theme.Space.Step[2])
		pad.PaddingLeft = UDim.new(0, Theme.Space.PadCard)
		pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
		return label
	end

	local function drawChips(words: CelebrateWords)
		for _, child in chips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, text in words.Chips do
			makeChip(text, index)
		end
		chips.Visible = #words.Chips > 0
	end

	-- The moment's colours: a nurse's rarity, a branch theme's (Rebirth: its Roof for the ribbon and rays, its Trim
	-- for the ring; never its Wall: the walls stay the plot colour), else the kind's accent.
	local function colorsOf(words: CelebrateWords): (Color3, Color3?)
		local accent = if words.Rarity
			then Kit.rarityColor(words.Rarity)
			else ACCENTS[words.Kind] or Theme.Colors.Primary
		local themed = words.Colors
		if themed then
			local roof = fromHex(themed[2], accent)
			local trim = fromHex(themed[3], Theme.Colors.Paper)
			return roof, trim
		end
		return accent, nil
	end

	local function draw(words: CelebrateWords)
		local accent, trim = colorsOf(words)
		ribbon.BackgroundColor3 = accent
		title.Text = words.Icon .. " " .. words.Title
		sub.Text = words.Sub
		sub.Visible = words.Sub ~= ""

		face:ClearAllChildren()
		local nurse = if words.NurseId then rawget(data.Nurses, words.NurseId) else nil
		local guide = if words.Portrait == "Guide" and type(data.Guide) == "table" then data.Guide else nil
		if nurse or guide then
			local portrait = Hud.portrait(if nurse then nurse.Look else guide.Look)
			portrait.ZIndex = 3
			portrait.Parent = face
		else
			Kit.label({
				Name = "Icon",
				Text = words.Icon,
				TextScaled = true,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = face,
			})
		end
		bubble.BackgroundColor3 = if nurse then Kit.lighten(accent, 0.55) else Theme.Colors.Paper

		local frame = ring:FindFirstChild("RarityFrame")
		if frame then
			frame:Destroy()
		end
		local trimStroke = ring:FindFirstChild("ThemeTrim")
		if trimStroke then
			trimStroke:Destroy()
		end
		if words.Rarity then
			table.insert(stopFx, Kit.rarityFrame(ring, words.Rarity))
		elseif trim then
			-- A branch theme: its trim colour rings the bubble.
			local stroke = Kit.stroke(ring, trim, Theme.Stroke.Panel + Theme.Stroke.Fine)
			stroke.Name = "ThemeTrim"
		end
		if words.Sticker then
			sticker.Text = words.Sticker
			sticker.BackgroundColor3 = accent
			sticker.Visible = true
		elseif words.Kind == "NewNurse" then
			sticker.Text = "NEW!"
			sticker.BackgroundColor3 = Theme.Colors.Dot
			sticker.Visible = true
		elseif words.Rarity then
			local rarity = rawget(data.Rarities, words.Rarity)
			sticker.Text = if rarity then rarity.Icon else ""
			sticker.BackgroundColor3 = accent
			sticker.Visible = rarity ~= nil
		else
			sticker.Visible = false
		end

		drawChips(words)
		comingText.Text = words.Next or ""
		comingUp.Visible = words.Next ~= nil
		-- The button: "🃏 Pick a card!" after a rebirth (it opens the perk cards), else "🎉 Yay!".
		local picks = words.Action == "Perks"
		yay.Text = if picks then "🃏 Pick a card!" else "🎉 Yay!"
		yay.Size = UDim2.fromOffset(if picks then 290 else 220, 64)
	end

	-- Things the reward leaves behind as it closes: cash into 💰, a new nurse into 👩‍⚕️, a branch's 🌳 into 🛒.
	local function afterClose(words: CelebrateWords)
		if words.Cash and words.Cash > 0 then
			Hud.fly(nil, "💰", "Cash", Kit.Juice.coins(words.Cash))
		end
		if words.NurseId then
			local nurse = rawget(data.Nurses, words.NurseId)
			Hud.fly(nil, if nurse then nurse.Icon else "👩‍⚕️", "Nurses", 1)
		end
		if words.Points and words.Points > 0 then
			Hud.fly(nil, "🌳", "Shop", math.clamp(words.Points + 2, 3, 8))
		end
	end

	local function bindClose(on: boolean)
		if not on then
			ContextActionService:UnbindAction(CLOSE_ACTION)
			return
		end
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState: Enum.UserInputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			closeNow(false)
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonB)
	end

	-- The chips spring in one after another (from `from`, so chips folded in later pop on their own).
	local function popChips(mine: number, from: number)
		local index = 0
		for _, child in chips:GetChildren() do
			if child:IsA("GuiObject") then
				index += 1
				if index >= from then
					task.delay(0.35 + (index - from + 1) * 0.09, function()
						if token == mine and child.Parent then
							Kit.bump(child)
							Hud.sound("Pop", 0.5)
						end
					end)
				end
			end
		end
	end

	local function show(words: CelebrateWords)
		token += 1
		local mine = token
		current = words
		openedAt = os.clock()
		local calm = Kit.reducedMotion()
		clearFx() -- anything the last one left (its close animation was cut short)
		draw(words)

		gui.Enabled = true
		if calm then
			dim.BackgroundTransparency = DIM
		else
			dim.BackgroundTransparency = 1
			TweenService:Create(dim, Theme.Tween.Fade, { BackgroundTransparency = DIM }):Play()
		end
		Kit.popIn(stage)
		local raysColor = if words.Colors
			then (colorsOf(words))
			else Kit.lighten(ACCENTS[words.Kind] or Theme.Colors.Cash, 0.2)
		table.insert(stopFx, Kit.celebrate(core, raysColor))
		Kit.confetti(rain, Theme.Juice.ConfettiPieces + (if words.Kind == "Rebirth" then 24 else 12))
		Hud.sound(words.Sound)

		-- The reward springs in, then the title, then each chip.
		if not calm then
			Kit.punch(bubble, 0.3, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
			bubble.Rotation = -14
			TweenService:Create(bubble, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Rotation = 0,
			}):Play()
			task.delay(0.18, function()
				if token == mine then
					Kit.punch(ribbon, 1.25, Theme.Tween.Bump)
				end
			end)
			if words.Sticker then
				task.delay(0.3, function()
					if token == mine then
						Kit.punch(sticker, 1.6, Theme.Tween.Bump)
					end
				end)
			end
			popChips(mine, 1)
			if words.Kind == "Rebirth" then
				-- A second wave of confetti as the new branch "opens".
				task.delay(0.6, function()
					if token == mine then
						Kit.confetti(rain, Theme.Juice.ConfettiPieces)
					end
				end)
			end
		else
			bubble.Rotation = 0
		end

		bindClose(true)
		if usesDirectionalFocus() then
			GuiService.SelectedObject = yay
		end
		task.delay(Theme.Juice.CelebrateSeconds + (EXTRA_SECONDS[words.Kind] or 0), function()
			if token == mine then
				closeNow(false)
			end
		end)
	end

	local function nextOne()
		if showing then
			return
		end
		showing = true
		task.spawn(function()
			while #queue > 0 do
				-- The first-session tutorial stays quiet: wait for it to end (its own finale shows at once).
				while TutorialLogic.active(ctx.State.Tutorial) and not Words.DURING_TUTORIAL[queue[1].Kind] do
					task.wait(1)
				end
				-- One nobody tapped for (a nurse levelling from cures, a lone unlock) never covers a treat card: its dim
				-- would catch the mini-game's taps. It waits for the card to close.
				local head: CelebrateWords? = queue[1]
				while head and Words.PASSIVE[head.Kind] and MiniGames.isOpen() do
					task.wait(0.25)
					head = queue[1]
				end
				local words = table.remove(queue, 1) :: CelebrateWords
				local ok, err = pcall(show, words)
				if not ok then
					warn("[Celebrate] show failed:", err)
					current = nil
				end
				while current do
					task.wait(0.1)
				end
				task.wait(0.25)
			end
			showing = false
		end)
	end

	-- byButton: the 🎉 / 🃏 button (a Rebirth's then opens the perk cards). A tap on the dim, ButtonB or the time
	-- running out only close.
	closeNow = function(byButton: boolean?)
		local words = current
		if not words then
			return
		end
		current = nil
		token += 1
		bindClose(false)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		Hud.sound("Close")
		local function finish()
			if current == nil then -- not already showing the next one
				clearFx()
				gui.Enabled = false
			end
		end
		if Kit.reducedMotion() then
			finish()
		else
			TweenService:Create(dim, Theme.Tween.Fade, { BackgroundTransparency = 1 }):Play()
			Kit.popOut(stage, finish)
		end
		afterClose(words)
		ctx.fire("CelebrateClosed", words.Kind)
		if byButton == true and words.Action == "Perks" then
			ctx.fire("Open", "Branch", "Perks")
		end
	end

	yay.Activated:Connect(function()
		closeNow(true)
	end)
	-- A treat card opening must stay playable: whatever celebration is up closes (its dim sits above the card and
	-- would catch the mini-game's taps). The server already granted what it showed.
	ctx.on("TreatStart", function()
		if current then
			closeNow(false)
		end
	end)
	dim.Activated:Connect(function()
		if os.clock() - openedAt >= TAP_GUARD then
			closeNow(false)
		end
	end)

	-- An Unlock joins the Rebirth it came with (waiting in the queue, or on screen now) as chips.
	local function foldUnlock(info: any): boolean
		if type(info) ~= "table" or info.Kind ~= "Unlock" then
			return false
		end
		local target = queue[#queue]
		if not (target and target.Kind == "Rebirth") then
			target = if current and current.Kind == "Rebirth" then current else nil
		end
		if not target then
			return false
		end
		local before = #target.Chips
		if not Words.fold(target, info.Unlock, wordsData) then
			return false
		end
		if target == current and #target.Chips > before then
			drawChips(target)
			if not Kit.reducedMotion() then
				popChips(token, before + 1)
			end
		end
		return true
	end

	ctx.on("Celebrate", function(info: any)
		if foldUnlock(info) then
			return
		end
		local words = Words.of(info, wordsData, Workspace:GetServerTimeNow())
		if not words then
			return
		end
		if Words.DURING_TUTORIAL[words.Kind] then
			table.insert(queue, 1, words) -- the tutorial's finale never waits behind the screens the tutorial holds
		elseif #queue >= MAX_QUEUE then
			return
		else
			table.insert(queue, words)
		end
		nextOne()
	end)
end

return Celebrate
