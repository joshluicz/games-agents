--!strict
-- The Nurse Belt: one shared conveyor along the town's main street, where nurses ride by and anyone can hire the
-- one they see, for in-game cash (depth-update design §2 and §7, build plan §B4/§B8; memory-20261116-012/-013/-017).
-- Server only. OWNER: T3 (Progression v2 too). Cash only; no Robux anywhere on the belt (red line 3). Every odd, the
-- event odds too, is on its sign.
--
-- Progression v2 (build plan §B8 "T3 NurseBelt"): a hire also needs the rarity's rebirths (Logic/Belt.gate: Mythic and
-- Secret from R1, "🏢 R1 first!") and roster room for a new nurse (Logic/Nurse.canAdd: "Roster full: sell or list
-- one"); the price takes 🏷️ Bargain off (Pure.bargainPrice; UI/BeltView shows the same number). 🔭 Belt Scout: while
-- a perk owner is in the server, the next arrival's rarity is rolled one arrival early (right after an arrival, or
-- when an owner joins or picks the perk), with the odds on the sign at that moment (its Event says which), and sent
-- with the BeltScout remote to the perk owners only; the arrival then uses that roll, but only while the sign still
-- shows those odds: when Night Rush or Golden Hour starts or ends in between, the early roll is thrown away, rolled
-- again with the new odds and sent again (every arrival has exactly the sign's odds, for everyone). The sign's gate
-- line says "🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1". The nurse house's NextLamp part glows brighter on the client as
-- the next nurse nears (the belt model's NextArrivalAt attribute: a GetServerTimeNow time; never a number on
-- screen, §E9).
--
-- Where (Joshua, 2026-11-16: "conveyor belt should be on the main road"; 2026-11-17, memory-20261117-001 #3: down the
-- road's CENTRE line): Config.Belt.Offset puts its start (the nurse house) just inside the east welcome arch, on the
-- centre line (z = 0); it runs Config.Belt.Length studs west (Config.Belt.Heading 180) to the cloud just inside the
-- west arch, past every plot's gate, so a rider is in hire reach (HireDistance) of every gate as it passes. The Hall
-- of Fame garden (past the west arch), both arches and the spawn plaza (the street's row-2 half) stay clear. The
-- conveyor's top is BELT_TOP (0.9 studs) above the street and its rails and rollers don't collide, so anyone can step
-- over it anywhere: crossing the street between the two rows stays easy. Riders face the plaza (+z, toward
-- TownSpawn: Pure.riderFacing).
-- The look (look build plan §B5, T2; art-direction §4.1/§4.4): a warm-white bed with a yellow stripe, a dark conveyor,
-- yellow rails, the nurse house in studded purple under a dark roof with "👩‍⚕️ NURSES" floating over its door. The odds
-- Sign stands apart from the belt at Config.Belt.SignOffset (the plaza's west end), facing TownSpawn: a navy plate
-- (World/Parts.navyPlate) with "🎲 NURSE ODDS" floating above it, every odd (day and Night Rush, the Golden Hour odd),
-- the gate lines and the pity count, Pure.SIGN wide (it fits the 9.2 studs tests/TownLayout.spec allows), and a
-- "🎲 See odds" ProximityPrompt (OddsPrompt) that only opens UI/BeltView's odds popup on the client.
--
--   NurseBelt.start()
--       builds Workspace.NurseBelt from Config.Town.Origin + Config.Belt.Offset (riders move along Heading for
--       Config.Belt.Length studs): BeltStart and BeltEnd (invisible anchored markers on the conveyor's top: a rider
--       stands at BeltStart.Position:Lerp(BeltEnd.Position, alpha)), Conveyor (its top face carries the SurfaceGui
--       ConveyorGui > Clip > Stripes for the client to scroll; attributes StripeStuds and StudsPerSecond), Sign
--       (SurfaceGui OddsGui: the floating title and a navy Plate with every odd now, day and night, the Golden Hour
--       odds, the Lv 3 and R1 gates, the pity count; its ProximityPrompt OddsPrompt "🎲 See odds"), NextLamp (a Part
--       with a PointLight over the house door; added to a kit belt that lacks one) and Riders (Folder). A Model at
--       ServerStorage.ClinicKit.NurseBelt with the same child names replaces the placeholder (its pivot = the belt's
--       start on the street, its +X along the belt; no scripts; its Sign stays where the kit put it and gets the same
--       plate and prompt).
--       Then it runs the belt: a rider every Config.Belt.ArriveSeconds (Logic/Belt.roll with the Night Rush and
--       Golden Hour odds and the server-wide pity), Workspace attributes NightRush (= IsNight), GoldenHour,
--       GoldenStartsAt, GoldenEndsAt (GetServerTimeNow times of the current or next window) and BeltPity (arrivals
--       left before a guaranteed Rare+), the Shout remote, and HireNurse. Riders face the plaza (TownSpawn's side).
--   NurseBelt.hire(p, riderId): (ok, message)
--       the rider exists and isn't hired or leaving · Config.Belt.HireCooldown per player · the player is within
--       HireDistance of the rider's formula position (Logic/Belt.alpha, never the part) · Logic/Belt.gate (Epic and
--       up need hospital Lv 3: "🏥 Lv 3 hospital first!"; Mythic and Secret the first rebirth: "🏢 R1 first!") ·
--       Logic/Nurse.canAdd (roster room, the level cap) · price = Pure.bargainPrice(Logic/Belt.price(rarity,
--       Levels.level(p)), Bargain) -> Nurses.grant(.., "Belt") (the charge and the copy in one update).
--       The rider spins, hops off and walks toward the hirer's clinic, then poofs. A hired Common or Rare that leaves
--       no other nurse riding brings the next arrival to ReplaceSeconds from now (Pure.afterHire), so the belt is
--       never left empty, yet hiring can't speed the belt up while others still ride. Nothing yields between the
--       checks and the grant, so a rider is never hired twice.
--   NurseBelt.odds(): { [Rarity]: number }   the odds right now (percent)
--   NurseBelt.goldenHour(): boolean
--   NurseBelt.Pure                           the pure helpers below (a scratch Lune harness tests them)
--
-- Riders: Riders.Rider_<RiderId> (NurseBuilder.build), PrimaryPart Root, attributes RiderId, NurseId, Rarity, Role,
-- StartAt (GetServerTimeNow when it stepped on), RideSeconds, Hired, Event ("" | "NightRush" | "GoldenHour": the
-- event whose odds rolled it). Root.HireAttachment.HirePrompt (ActionText "Hire", ObjectText the rarity icon and
-- name: BeltView shows each viewer's own price, no line of sight, no hold, 14 studs). While riding, the server writes
-- Root.CFrame once every Config.Belt.ServerStepSeconds and BeltView glides it every frame. When a rider leaves
-- (hired, or off the far end into the cloud) it gets the CreatureMotion tag and hops by the creature-motion
-- contract (NurseBuilder.hop): from then on BeltView must stop moving it.
-- Shouts (to everyone): { Kind = "Arrival", RiderId, NurseId, Rarity } for Epic and up (they also glow),
-- { Kind = "Hired", NurseId, Rarity, By = DisplayName } for Legendary and up, { Kind = "Golden", On, EndsAt }.
-- The Journal: a rider within SEEN_DISTANCE of a player (checked when it steps on and every server step) marks it
-- "Seen" for that player (Nurses.markSeen).
-- Night Rush follows Workspace.IsNight (the game's clock) and Golden Hour follows server uptime, never real-world
-- dates. Studio-only test switches (a live server ignores them): Workspace attribute BeltForce = "<Rarity>" makes
-- every arrival that rarity (except when the pity is due, so 15 forced Commons are followed by a Rare+), and
-- ForceGolden = true starts a Golden Hour now.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local BeltLogic = require(Shared.Logic.Belt)
local NurseLogic = require(Shared.Logic.Nurse)
local RebirthLogic = require(Shared.Logic.Rebirth)
local NursesData = require(Shared.Data.Nurses)
local PerksData = require(Shared.Data.Perks)
local Rarities = require(Shared.Data.Rarities)
local TreeData = require(Shared.Data.Tree)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Levels = require(script.Parent.Levels)
local NurseBuilder = require(script.Parent.NurseBuilder)
local Nurses = require(script.Parent.Nurses)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Parts = require(script.Parent.World.Parts)
local Studs = require(script.Parent.World.Studs)

local NurseBelt = {}

------------------------------------------------------------------------------------------------------------------
-- Tuning (looks and feel; the rules' numbers are in Config.Belt)
------------------------------------------------------------------------------------------------------------------

local MODEL_NAME = "NurseBelt"
local MOTION_TAG = "CreatureMotion"
local TICK = 0.25 -- the belt's clock: arrivals, Golden Hour and the server step are checked this often
-- Riders already on the belt when the server opens (as if it had been running), so it never starts empty: as many as
-- the cadence keeps on it (100 s rides, one every 40 s: 2, plus the one that steps on at once).
local PREFILL = math.max(0, math.floor((Config.Belt.RideSeconds - 1) / Config.Belt.ArriveSeconds))
-- Studs: a player this close to a rider has seen it (the Journal's silhouette fills in). Config.Belt.SeenDistance once
-- the Foundation adds it.
local SEEN_DISTANCE: number = tonumber((Config.Belt :: any).SeenDistance) or 100
local PROMPT_DISTANCE = 14
local BELT_WIDTH = 5
local BELT_TOP = 0.9 -- the conveyor's top, above the street: low enough to step over anywhere
local STRIPE_STUDS = 4
local STRIPE_PIXELS_PER_STUD = 3 -- the conveyor's stripes (the 272-stud conveyor stays under 1,000 px wide)
local FALLBACK_GROUND_TOP = 0.5 -- PlotBuilder's street top above Config.Town.Origin.Y (if ClinicTown is missing)
local SIGN_PIXELS_PER_STUD = 30
local PROMPT_NAME = "OddsPrompt" -- the sign's "🎲 See odds" prompt (UI/BeltView opens the odds popup)

local WHITE = Palette.White
local WORLD = Palette.World
local ACCENT = Palette.Accent

local MSG = {
	Gone = "Missed it! Next one 💛",
	Taken = "Already hired! 💛",
	Wait = "Wait a moment! ⏳",
	Closer = "Get closer! 👣",
}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services; the only upvalue is Logic/Belt as `BeltLogic`: a scratch Lune harness loads this
-- block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.RARITIES = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

function Pure.rank(rarity: any): number
	return table.find(Pure.RARITIES, rarity) or 0
end

-- The sign's percent: "70%", "39.5%", "0.5%"; "–" when it can't come now.
function Pure.percent(value: number): string
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return "–"
	end
	local tenths = math.floor(value * 10 + 0.5)
	if tenths % 10 == 0 then
		return string.format("%d%%", tenths // 10)
	end
	return string.format("%.1f%%", tenths / 10)
end

-- The sign's status line (6 words or fewer).
function Pure.status(nightRush: boolean, golden: boolean, boost: number): string
	if golden and nightRush then
		return "👑 Golden Night Rush!"
	elseif golden then
		return "👑 Golden Hour!"
	elseif nightRush then
		return string.format("🌙 Night Rush! Rare+ ×%s", tostring(boost))
	end
	return "☀️ Day odds"
end

-- After a hire: a hired Common or Rare that leaves no other nurse riding (`others` = riders still open) is replaced
-- quickly: the next arrival comes ReplaceSeconds from now (never later than it was already due). While others still
-- ride, the belt keeps its cadence, so hiring never makes rare nurses come faster.
function Pure.afterHire(nextArrival: number, now: number, rarity: string, cfg: any, others: number): number
	if (rarity == "Common" or rarity == "Rare") and others <= 0 then
		return math.min(nextArrival, now + cfg.Belt.ReplaceSeconds)
	end
	return nextArrival
end

-- Legendary and up: a server-wide "<name> hired a ..." shout.
function Pure.hiredShout(rarity: string): boolean
	return Pure.rank(rarity) >= 4
end

-- The Golden Hour window at `uptime` (server seconds): Logic/Belt.golden, or a forced window that started at
-- `forcedFrom` (the Studio switch). (active, startsAt, endsAt) in uptime seconds.
function Pure.golden(cfg: any, uptime: number, forcedFrom: number?): (boolean, number, number)
	if forcedFrom then
		local length = cfg.Belt.GoldenSeconds
		if uptime >= forcedFrom and uptime < forcedFrom + length then
			return true, forcedFrom, forcedFrom + length
		end
	end
	return BeltLogic.golden(cfg, uptime)
end

-- The Studio switch BeltForce: that rarity, unless the pity is due and it isn't Rare+ (so the pity can be tested).
function Pure.forced(value: any, pityDue: boolean): string?
	if type(value) ~= "string" or Pure.rank(value) == 0 then
		return nil
	end
	if pityDue and Pure.rank(value) < 2 then
		return nil
	end
	return value
end

-- The event whose odds rolled an arrival.
function Pure.event(nightRush: boolean, golden: boolean): string
	return if golden then "GoldenHour" elseif nightRush then "NightRush" else ""
end

-- Progression v2. 🏷️ Bargain (Logic/Rebirth.effects .Bargain, a fraction) off a belt price, rounded once more.
-- UI/BeltView's Pure.bargainPrice is the same formula (tests/AgencyServer.spec checks they agree), so the card shows
-- exactly what the hire charges.
function Pure.bargainPrice(price: any, bargain: any): number
	local p = if type(price) == "number" and price == price and price ~= math.huge then math.max(0, price) else 0
	local off = if type(bargain) == "number" and bargain == bargain then math.clamp(bargain, 0, 0.9) else 0
	return math.floor(p * (1 - off) + 0.5)
end

-- The sign's gate lines (each 6 words or fewer): who may hire what. "🏥 Epic+ from Lv 3" (the hospital level Epic
-- needs; Epic and up share it), then one "🏢 Mythic/Secret from R1" per rebirth count that some rarity needs.
function Pure.gateLines(cfg: any): { string }
	local lines: { string } = {}
	local level = BeltLogic.minLevel(cfg, "Epic")
	if level > 1 then
		table.insert(lines, string.format("🏥 Epic+ from Lv %d", level))
	end
	local counts: { number } = {}
	local names: { [number]: { string } } = {}
	for _, rarity in Pure.RARITIES do
		local needed = BeltLogic.minRebirths(cfg, rarity)
		if needed > 0 then
			if not names[needed] then
				names[needed] = {}
				table.insert(counts, needed)
			end
			table.insert(names[needed], rarity)
		end
	end
	for _, needed in counts do
		table.insert(lines, string.format("🏢 %s from R%d", table.concat(names[needed], "/"), needed))
	end
	return lines
end

-- The same lines on one row: "🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1".
function Pure.gateText(cfg: any): string
	return table.concat(Pure.gateLines(cfg), " · ")
end

-- A refused hire's reply for a gate (Logic/Belt.gate): "🏥 Lv 3 hospital first!" · "🏢 R1 first!".
function Pure.gateMessage(gate: string): string
	if string.sub(gate, 1, #"🏥") == "🏥" then
		return gate .. " hospital first!"
	end
	return gate .. " first!"
end

-- The look overhaul (look build plan §B5). The odds sign, in studs: the navy plate (Width x Height, its bottom edge
-- Bottom above the ground) with the floating title (Title tall) above it. Facing TownSpawn from Config.Belt.SignOffset,
-- its width runs along the plaza's depth: tests/TownLayout.spec allows at most 9.2 there.
Pure.SIGN = table.freeze({ Width = 9, Height = 8.5, Bottom = 1.6, Title = 1.8, Depth = 0.3 })

-- A flat unit direction from (fromX, fromZ) toward (toX, toZ), or the fallback when they're under a stud apart.
function Pure.toward(fromX: number, fromZ: number, toX: number, toZ: number, fallbackX: number, fallbackZ: number)
	local dx, dz = toX - fromX, toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1 then
		return fallbackX, fallbackZ
	end
	return dx / length, dz / length
end

-- Which way riders face (memory-20261117-001 #3): across the belt, toward the plaza (TownSpawn at (toX, toZ)). With
-- the belt running along (dirX, dirZ) from (fromX, fromZ), that is the part of the way to the spawn that crosses the
-- belt; a spawn on the belt's own line (under a stud off it) leaves them facing back up the belt.
function Pure.riderFacing(dirX: number, dirZ: number, fromX: number, fromZ: number, toX: number, toZ: number)
	local dx, dz = toX - fromX, toZ - fromZ
	local along = dx * dirX + dz * dirZ
	local ax, az = dx - dirX * along, dz - dirZ * along
	local length = math.sqrt(ax * ax + az * az)
	if length <= 1 then
		return -dirX, -dirZ
	end
	return ax / length, az / length
end
-- PURE-END

NurseBelt.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------------------------

type Rider = {
	Id: number,
	NurseId: string,
	Rarity: string,
	Model: Model,
	Root: BasePart,
	Prompt: ProximityPrompt,
	StartAt: number,
	Ride: number,
	Hired: boolean,
	Claimed: boolean, -- a hire is being granted right now
	Leaving: boolean,
	SeenBy: { [Player]: boolean },
}

type SignView = {
	Status: TextLabel,
	Day: { [string]: TextLabel },
	Night: { [string]: TextLabel },
	DayHead: TextLabel,
	NightHead: TextLabel,
	Golden: TextLabel,
	Gate: TextLabel,
	Pity: TextLabel,
}

type Belt = {
	Model: Model,
	Start: BasePart,
	End: BasePart,
	Riders: Instance,
	GroundY: number,
	Dir: Vector3, -- along the belt
	Side: Vector3, -- across it
	Facing: CFrame, -- a rider's rotation: looking across the belt, toward the plaza (TownSpawn)
	Sign: SignView?,
}

local belt: Belt? = nil
local riders: { [number]: Rider } = {}
local lastRiderId = 0
local dry = 0 -- arrivals in a row without a Rare+ (server-wide)
local nextArrival = 0 -- GetServerTimeNow time
local nextStep = 0
local lastHire: { [Player]: number } = {}
local golden = { Active = false, StartsAt = 0, EndsAt = 0 }
local forcedFrom: number? = nil -- uptime seconds of a forced Golden Hour (Studio switch)
local serverStart = Workspace:GetServerTimeNow() - time()
local rng = Random.new()
local failures: { [string]: number } = {}
-- 🔭 Belt Scout: the next arrival's rarity, rolled one arrival early while a perk owner is here (nil = roll it when it
-- arrives), and who has the perk now.
type Upcoming = { Rarity: string, Event: string }
local upcoming: Upcoming? = nil
local scouts: { [Player]: boolean } = {}
local NEXT_ATTRIBUTE = "NextArrivalAt" -- on the belt model: when the next nurse comes (the house lamp, BeltView)
local LAMP_NAME = "NextLamp"

local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[NurseBelt] " .. label .. " failed: " .. tostring(err))
	end
end

local function rarityInfo(rarity: string): any
	local info = rawget(Rarities :: any, rarity)
	return if type(info) == "table" then info else nil
end

local function rarityColor(rarity: string): Color3
	local info = rarityInfo(rarity)
	local ok, color = pcall(Color3.fromHex, if info then info.Color else "#B4BCCB")
	return if ok then color else WHITE
end

local function nurseOf(nurseId: string): any
	local nurse = rawget(NursesData :: any, nurseId)
	return if type(nurse) == "table" then nurse else nil
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function nightRush(): boolean
	return Workspace:GetAttribute("IsNight") == true
end

local function rebirthsOf(data: any): number
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	return if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
end

local function effectsOf(data: any): RebirthLogic.Effects
	return RebirthLogic.effects(data, Config, PerksData, TreeData)
end

local function knownNurse(nurseId: string): boolean
	return nurseOf(nurseId) ~= nil
end

------------------------------------------------------------------------------------------------------------------
-- Building the belt
------------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3): Part
	local p = part(parent, name, Vector3.one * diameter, cf, color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, color: Color3)
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cf, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function marker(parent: Instance, name: string, cf: CFrame): Part
	local p = part(parent, name, Vector3.new(1, 0.2, 1), cf, WHITE)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- The nurse house's "next nurse" lamp: a soft ball with a dim light (no shadows). The client sets how bright it is.
local function addLamp(parent: Instance, cf: CFrame): Part
	local lamp = ball(parent, LAMP_NAME, 1.1, cf, ACCENT.Yellow)
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = WORLD.Lamp
	light.Brightness = 0.3
	light.Range = 9
	light.Shadows = false
	light.Parent = lamp
	return lamp
end

local function streetTop(): number
	local town = Workspace:FindFirstChild("ClinicTown")
	local street = town and town:FindFirstChild("Street")
	if street and street:IsA("BasePart") then
		return street.Position.Y + street.Size.Y / 2
	end
	return Config.Town.Origin.Y + FALLBACK_GROUND_TOP
end

-- The stripes on the conveyor's top. The client scrolls Clip.Stripes left by one stripe and wraps (BeltView).
local function addStripes(conveyor: BasePart)
	local length = conveyor.Size.X
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ConveyorGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = STRIPE_PIXELS_PER_STUD
	gui.LightInfluence = 0.6
	gui.MaxDistance = 160
	local clip = Instance.new("Frame")
	clip.Name = "Clip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = gui
	local count = math.ceil(length / STRIPE_STUDS)
	local stripes = Instance.new("Frame")
	stripes.Name = "Stripes"
	stripes.BackgroundTransparency = 1
	stripes.Size = UDim2.fromScale((count + 1) * STRIPE_STUDS / length, 1)
	stripes.Parent = clip
	for i = 0, count do
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.BorderSizePixel = 0
		stripe.BackgroundColor3 = WHITE
		stripe.BackgroundTransparency = 0.55
		stripe.AnchorPoint = Vector2.new(0.5, 0)
		stripe.Size = UDim2.new(0, math.max(2, math.floor(0.75 * STRIPE_PIXELS_PER_STUD + 0.5)), 0.8, 0)
		stripe.Position = UDim2.fromScale((i + 0.5) / (count + 1), 0.1)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = stripe
		stripe.Parent = stripes
	end
	gui.Parent = conveyor
	conveyor:SetAttribute("StripeStuds", STRIPE_STUDS)
	conveyor:SetAttribute("StudsPerSecond", Config.Belt.Length / Config.Belt.RideSeconds)
end

local function placeholderBelt(frame: CFrame): Model
	local length = Config.Belt.Length
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	local bedHeight = BELT_TOP - 0.2

	-- The bed: warm white with a yellow stripe, a dark conveyor on top (its white stripes scroll), yellow rails, dark
	-- rollers at the ends. Only the bed and the conveyor collide, and the top is BELT_TOP (0.9) above the street: a step
	-- anyone walks over. It reads clearly on the dark road (art-direction §4.1: warm whites, never pure white).
	part(
		model,
		"BeltBed",
		Vector3.new(length + 3, bedHeight, BELT_WIDTH + 1.6),
		frame * CFrame.new(length / 2, bedHeight / 2, 0),
		WORLD.Trim
	)
	part(
		model,
		"BedStripe",
		Vector3.new(length + 3.05, 0.3, BELT_WIDTH + 1.65),
		frame * CFrame.new(length / 2, bedHeight * 0.5, 0),
		ACCENT.Yellow
	)
	local conveyor = part(
		model,
		"Conveyor",
		Vector3.new(length + 2, 0.2, BELT_WIDTH),
		frame * CFrame.new(length / 2, BELT_TOP - 0.1, 0),
		WORLD.Roof
	)
	addStripes(conveyor)
	for _, side in { -1, 1 } do
		local rail = cylinder(
			model,
			"Rail",
			length + 2,
			0.4,
			frame * CFrame.new(length / 2, BELT_TOP + 0.2, side * (BELT_WIDTH / 2 + 0.35)),
			ACCENT.Yellow
		)
		rail.CanCollide = false -- walk-through: the rails never stop anyone crossing
		rail.CanQuery = false
	end
	local alongZ = CFrame.Angles(0, math.pi / 2, 0)
	for _, x in { -1.4, length + 1.4 } do
		local roller = cylinder(
			model,
			"Roller",
			BELT_WIDTH + 1.7,
			bedHeight + 0.3,
			frame * CFrame.new(x, (bedHeight + 0.3) / 2, 0) * alongZ,
			WORLD.Roof
		)
		roller.CanCollide = false
	end

	-- The nurse house at the start: riders step out of its door onto the belt. Studded purple walls (whole studs: 5 x 8,
	-- the alignment rule), a warm-white band, a dark flat roof, and its name floating over the door. (The odds sign
	-- stands on its own at the plaza: buildSignStand.)
	local houseX, houseWidth, houseDepth, houseHeight = -4.5, 5, BELT_WIDTH + 3, 9
	local house = part(
		model,
		"NurseHouse",
		Vector3.new(houseWidth, houseHeight, houseDepth),
		frame * CFrame.new(houseX, houseHeight / 2, 0),
		ACCENT.Purple
	)
	house.CastShadow = true
	Studs.apply(house)
	part(
		model,
		"HouseStripe",
		Vector3.new(houseWidth + 0.05, 0.6, houseDepth + 0.05),
		frame * CFrame.new(houseX, houseHeight - 0.5, 0),
		WORLD.Trim
	)
	local roof = part(
		model,
		"Roof",
		Vector3.new(houseWidth + 0.6, 0.6, houseDepth + 0.6),
		frame * CFrame.new(houseX, houseHeight + 0.3, 0),
		WORLD.Roof
	)
	roof.CastShadow = true
	local door = part(
		model,
		"Door",
		Vector3.new(0.2, 4.2, BELT_WIDTH - 0.6),
		frame * CFrame.new(houseX + houseWidth / 2 + 0.05, 2.4, 0),
		Palette.Ink
	)
	door.CanCollide = false
	-- Its name in floating outlined letters on the door's face, over the lamp (art-direction §4.4: no board).
	local nameGui = Parts.surface(house, "HouseGui", Enum.NormalId.Right, 30, 220, 0)
	Parts.floatText(nameGui, "👩‍⚕️ NURSES", {
		Shadow = true,
		Size = UDim2.fromScale(0.9, 0.17),
		Position = UDim2.fromScale(0.05, 0.12),
	})

	-- The "next nurse" lamp over the door (§E9): BeltView brightens it as the next nurse nears. No numbers anywhere.
	addLamp(model, frame * CFrame.new(houseX + houseWidth / 2 + 0.35, 5.4, 0))

	-- The cloud cushion at the far end: unhired nurses hop off into it and poof home.
	local endX = length + 4.6
	local puffs: { { At: Vector3, Size: number } } = {
		{ At = Vector3.new(0, 1.2, 0), Size = 3.2 },
		{ At = Vector3.new(0.6, 1.0, 1.9), Size = 2.4 },
		{ At = Vector3.new(0.4, 1.0, -1.9), Size = 2.4 },
		{ At = Vector3.new(1.7, 0.8, 0.2), Size = 2 },
	}
	for _, puff in puffs do
		local cloud = ball(model, "Cloud", puff.Size, frame * CFrame.new(Vector3.new(endX, 0, 0) + puff.At), WORLD.Trim)
		cloud.CanCollide = false
	end

	marker(model, "BeltStart", frame * CFrame.new(0, BELT_TOP, 0))
	marker(model, "BeltEnd", frame * CFrame.new(length, BELT_TOP, 0))
	local folder = Instance.new("Folder")
	folder.Name = "Riders"
	folder.Parent = model
	model.WorldPivot = frame
	return model
end

-- The odds sign: a navy plate on two dark posts, the title floating above it (Pure.SIGN). The Sign part itself is
-- see-through (it only carries OddsGui, so the plate's round corners show); a dark backing just inside the plate's
-- edge keeps the plate solid from the front. `at` is the ground under its middle, its LookVector the way its Front
-- (the odds) faces: TownSpawn.
local function buildSignStand(model: Model, at: CFrame)
	local S = Pure.SIGN
	local tall = S.Height + S.Title
	local sign = part(
		model,
		"Sign",
		Vector3.new(S.Width, tall, S.Depth),
		at * CFrame.new(0, S.Bottom + tall / 2, 0),
		Palette.Navy
	)
	sign.Transparency = 1
	sign.CanCollide = false
	local back = part(
		model,
		"SignBack",
		Vector3.new(S.Width - 1.2, S.Height - 1.2, 0.2),
		at * CFrame.new(0, S.Bottom + S.Height / 2, S.Depth / 2 + 0.1),
		WORLD.Roof
	)
	back.CanCollide = false
	local postHeight = S.Bottom + S.Height - 0.4
	for _, side in { -1, 1 } do
		local x = side * (S.Width / 2 - 1.2)
		local post = part(
			model,
			"SignPost",
			Vector3.new(0.6, postHeight, 0.6),
			at * CFrame.new(x, postHeight / 2, S.Depth / 2 + 0.5),
			WORLD.Roof
		)
		post.CastShadow = true
	end
	return sign
end

-- The brother's belt, if it has what the game needs (BeltStart, BeltEnd and a Sign part).
local function kitBelt(frame: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild(MODEL_NAME)
	if not (template and template:IsA("Model")) then
		return nil
	end
	for _, name in { "BeltStart", "BeltEnd", "Sign" } do
		local child = template:FindFirstChild(name)
		if not (child and child:IsA("BasePart")) then
			warn("[NurseBelt] ClinicKit.NurseBelt needs a Part named " .. name .. "; using the placeholder")
			return nil
		end
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			warn("[NurseBelt] Removed a script from ClinicKit.NurseBelt:", descendant:GetFullName())
			descendant:Destroy()
		elseif descendant:IsA("Highlight") then
			descendant:Destroy() -- the perf budget: at most one Highlight in the world
		elseif descendant:IsA("Light") then
			descendant.Shadows = false -- the perf budget: no shadow-casting lights
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model.Name = MODEL_NAME
	model:PivotTo(frame)
	if not model:FindFirstChild("Riders") then
		local folder = Instance.new("Folder")
		folder.Name = "Riders"
		folder.Parent = model
	end
	for _, name in { "BeltStart", "BeltEnd" } do
		local markerPart = model:FindFirstChild(name) :: BasePart
		markerPart.Transparency = 1
		markerPart.CanCollide = false
		markerPart.CanQuery = false
	end
	local conveyor = model:FindFirstChild("Conveyor")
	if conveyor and conveyor:IsA("BasePart") and not conveyor:FindFirstChild("ConveyorGui") then
		addStripes(conveyor)
	end
	return model
end

------------------------------------------------------------------------------------------------------------------
-- The sign
------------------------------------------------------------------------------------------------------------------

local function textLabel(parent: Instance, name: string, text: string, size: UDim2, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BackgroundColor3 = WHITE
	label.Size = size
	label.Font = Palette.DisplayFont
	label.TextScaled = true
	label.TextColor3 = color or WHITE
	label.Text = text
	Palette.outlineText(label, 2)
	label.Parent = parent
	return label
end

local function cellCorner(label: TextLabel)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = label
end

local function buildSign(sign: BasePart): SignView
	local existing = sign:FindFirstChild("OddsGui")
	local gui: SurfaceGui
	if existing and existing:IsA("SurfaceGui") then
		gui = existing
		gui:ClearAllChildren()
	else
		gui = Instance.new("SurfaceGui")
		gui.Name = "OddsGui"
		gui.Face = Enum.NormalId.Front
	end
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	gui.LightInfluence = 0 -- the odds never dim at night
	gui.MaxDistance = 180

	-- The title floats over the plate (art-direction §4.4); the table sits on the navy plate (a board only where there
	-- is a table to read). A kit sign of another size keeps the same shares.
	local S = Pure.SIGN
	local titleShare = S.Title / (S.Title + S.Height)
	Parts.floatText(gui, "🎲 NURSE ODDS", {
		Gold = true,
		Shadow = true,
		Size = UDim2.fromScale(1, titleShare * 0.92),
		Position = UDim2.fromScale(0, 0),
	})
	local board = Parts.navyPlate(gui, {
		Size = UDim2.new(1, -8, 1 - titleShare, -8),
		Position = UDim2.fromScale(0.5, titleShare + (1 - titleShare) / 2),
	})
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.035, 0)
	padding.PaddingBottom = UDim.new(0.03, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = board
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0.008, 0)
	list.Parent = board

	local order = 0
	local function row(height: number): Frame
		order += 1
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. order
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, height)
		frame.LayoutOrder = order
		frame.Parent = board
		return frame
	end
	local function columns(frame: Frame): (UDim2, UDim2, UDim2)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0.02, 0)
		layout.Parent = frame
		return UDim2.fromScale(0.5, 1), UDim2.fromScale(0.23, 0.92), UDim2.fromScale(0.23, 0.92)
	end

	local status = textLabel(row(0.09), "Status", "", UDim2.fromScale(1, 1), Palette.Gold)

	local head = row(0.075)
	local nameSize, daySize, nightSize = columns(head)
	textLabel(head, "Name", "", nameSize).LayoutOrder = 1
	local dayHead = textLabel(head, "Day", "☀️", daySize)
	dayHead.LayoutOrder = 2
	local nightHead = textLabel(head, "Night", "🌙", nightSize)
	nightHead.LayoutOrder = 3

	local view: SignView = {
		Status = status,
		Day = {},
		Night = {},
		DayHead = dayHead,
		NightHead = nightHead,
		Golden = status, -- set below
		Gate = status, -- set below
		Pity = status, -- set below
	}
	for _, rarity in Rarities.Order do
		local info = rarityInfo(rarity)
		local line = row(0.075)
		local a, b, c = columns(line)
		local name =
			textLabel(line, "Name", (if info then info.Icon .. " " .. info.Name else rarity), a, rarityColor(rarity))
		name.LayoutOrder = 1
		name.TextXAlignment = Enum.TextXAlignment.Left
		local day = textLabel(line, "Day", "", b)
		day.LayoutOrder = 2
		cellCorner(day)
		local night = textLabel(line, "Night", "", c)
		night.LayoutOrder = 3
		cellCorner(night)
		view.Day[rarity] = day
		view.Night[rarity] = night
	end
	view.Golden = textLabel(row(0.075), "Golden", "", UDim2.fromScale(1, 1), Palette.Gold)
	view.Gate = textLabel(row(0.11), "Gate", "", UDim2.fromScale(1, 1)) -- two lines: the level and rebirth gates
	view.Pity = textLabel(row(0.075), "Pity", "", UDim2.fromScale(1, 1))
	gui.Parent = sign
	return view
end

-- The sign's "🎲 See odds" prompt: it only opens UI/BeltView's odds popup on the client (no server action), so it
-- never needs a remote. Low on the plate, where a kid reading it stands. Added once (a kit sign keeps its own).
local function addOddsPrompt(sign: BasePart)
	if sign:FindFirstChild(PROMPT_NAME, true) then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "OddsAttachment"
	attachment.Position = Vector3.new(0, -sign.Size.Y / 2 + math.min(3, sign.Size.Y / 2), 0)
	attachment.Parent = sign
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "🎲 See odds"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
end

local function setCell(label: TextLabel, text: string, active: boolean)
	if label.Text ~= text then
		label.Text = text
	end
	label.BackgroundTransparency = if active then 0 else 1
	label.TextColor3 = if active then Palette.Ink else WHITE
	local stroke = label:FindFirstChild("TextOutline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = not active
	end
end

local function refreshSign()
	local view = belt and belt.Sign
	if not view then
		return
	end
	local night = nightRush()
	local goldenOn = golden.Active
	view.Status.Text = Pure.status(night, goldenOn, Config.Belt.NightRushBoost)
	local day = BeltLogic.odds(Config, false, goldenOn)
	local nightOdds = BeltLogic.odds(Config, true, goldenOn)
	for _, rarity in Rarities.Order do
		setCell(view.Day[rarity], Pure.percent(day[rarity]), not night)
		setCell(view.Night[rarity], Pure.percent(nightOdds[rarity]), night)
	end
	setCell(view.DayHead, "☀️", not night)
	setCell(view.NightHead, "🌙", night)
	view.Golden.Text = "👑 Golden Hour: Secret " .. Pure.percent(Config.Belt.GoldenSecret)
	view.Gate.Text = table.concat(Pure.gateLines(Config), "\n")
	view.Pity.Text = "🎁 Rare+ in " .. tostring(BeltLogic.pityLeft(dry, Config))
end

------------------------------------------------------------------------------------------------------------------
-- Riders
------------------------------------------------------------------------------------------------------------------

local function formulaPosition(rider: Rider, now: number): Vector3
	local b = belt :: Belt
	return b.Start.Position:Lerp(b.End.Position, BeltLogic.alpha(rider.StartAt, now, rider.Ride))
end

local function formulaCFrame(rider: Rider, now: number): CFrame
	return CFrame.new(formulaPosition(rider, now)) * (belt :: Belt).Facing
end

local function removeRider(rider: Rider)
	riders[rider.Id] = nil
	rider.Model:Destroy()
end

local function poof(rider: Rider, at: Vector3)
	pcall(CreatureBuilder.effectAt, at + Vector3.new(0, 1.5, 0), "Pop")
	removeRider(rider)
end

-- Off the belt: the rider leaves the belt formula and hops by the creature-motion contract.
local function startLeaving(rider: Rider, now: number): CFrame
	rider.Leaving = true
	rider.Prompt.Enabled = false
	local from = formulaCFrame(rider, now)
	rider.Root.CFrame = from
	CollectionService:AddTag(rider.Model, MOTION_TAG)
	return from
end

-- Nobody hired it: off the far end into the cloud, a bounce, and it poofs home.
local function fallOff(rider: Rider, now: number)
	local b = belt :: Belt
	local from = startLeaving(rider, now)
	task.spawn(function()
		local landing = Vector3.new(from.X, b.GroundY + 0.6, from.Z) + b.Dir * 4.4
		local to = CFrame.new(landing) * CFrame.lookAt(Vector3.zero, b.Dir).Rotation
		if NurseBuilder.hop(rider.Model, from, to, 1.6, 0.6) then
			NurseBuilder.hop(rider.Model, to, to, 0.6, 0.35)
		end
		poof(rider, landing)
	end)
end

-- Hired: a happy spin, off the side toward the hirer's clinic, a few hops, and it poofs (it's at the clinic now).
local function leaveHired(rider: Rider, player: Player, now: number)
	local b = belt :: Belt
	local from = startLeaving(rider, now)
	local plot = Plots.getPlot(player)
	local hirer = characterRoot(player)
	local target = if plot then plot.Model:GetPivot().Position elseif hirer then hirer.Position else from.Position
	task.spawn(function()
		local model = rider.Model
		if not NurseBuilder.hop(model, from, from, 1.8, 0.55, math.pi * 2) then
			return poof(rider, from.Position)
		end
		local across = (target - from.Position):Dot(b.Side)
		local side = if across < 0 then -1 else 1
		local off = Vector3.new(from.X, b.GroundY, from.Z) + b.Side * side * (BELT_WIDTH / 2 + 3)
		local heading = Vector3.new(target.X - off.X, 0, target.Z - off.Z)
		local direction = if heading.Magnitude > 0.1 then heading.Unit else b.Side * side
		local pose = CFrame.lookAt(off, off + direction)
		if not NurseBuilder.hop(model, from, pose, 2, 0.5) then
			return poof(rider, off)
		end
		for _ = 1, 3 do
			local nextAt = pose.Position + direction * 3
			local nextPose = CFrame.lookAt(nextAt, nextAt + direction)
			if not NurseBuilder.hop(model, pose, nextPose, 0.8, 0.32) then
				break
			end
			pose = nextPose
		end
		poof(rider, pose.Position)
	end)
end

local function seenBy(rider: Rider, now: number, positions: { [Player]: Vector3 })
	local at = formulaPosition(rider, now)
	local fresh: { Player } = {}
	for player, position in positions do
		if not rider.SeenBy[player] and (position - at).Magnitude <= SEEN_DISTANCE then
			rider.SeenBy[player] = true
			table.insert(fresh, player)
		end
	end
	if #fresh > 0 then
		local ok, err = pcall(Nurses.markSeen, rider.NurseId, fresh)
		if not ok then
			report("Nurses.markSeen", err)
		end
	end
end

local function playerPositions(): { [Player]: Vector3 }
	local positions: { [Player]: Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local root = characterRoot(player)
		if root then
			positions[player] = root.Position
		end
	end
	return positions
end

local function onPrompt(player: Player, riderId: number)
	if not Remotes.allow(player, "HireNurse") then
		Remotes.toast(player, Remotes.TOO_FAST)
		return
	end
	local rider = riders[riderId]
	local isNew = false
	if rider then
		local data = PlayerData.get(player)
		isNew = data ~= nil and data.Nurses[rider.NurseId] == nil
	end
	local ok, hired, message = pcall(NurseBelt.hire, player, riderId)
	if not ok then
		report("a hire", hired)
		Remotes.toast(player, Remotes.OOPS)
		return
	end
	-- A first copy gets the big NewNurse celebration; everything else (a level-up, a refusal) a toast.
	if type(message) == "string" and message ~= "" and not (hired and isNew) then
		Remotes.toast(player, message)
	end
end

-- The next arrival's rarity, with the odds on the sign right now (Night Rush, Golden Hour, the pity, BeltForce), and
-- the event whose odds rolled it.
local function rollRarity(): Upcoming
	local night = nightRush()
	local goldenOn = golden.Active
	local pity = BeltLogic.pityDue(dry, Config)
	local forced = if RunService:IsStudio() then Pure.forced(Workspace:GetAttribute("BeltForce"), pity) else nil
	local rarity = forced or BeltLogic.roll(BeltLogic.odds(Config, night, goldenOn), rng:NextNumber(), pity)
	return { Rarity = rarity, Event = Pure.event(night, goldenOn) }
end

local function sendScout(player: Player)
	local ahead = upcoming
	if ahead and player.Parent == Players then
		Remotes.BeltScout:FireClient(player, { Rarity = ahead.Rarity, Event = ahead.Event })
	end
end

-- 🔭 Belt Scout: roll the next arrival now (one arrival early) if it isn't rolled yet, and tell `only` (one player who
-- just got the perk) or every perk owner.
local function scoutAhead(only: Player?)
	if upcoming == nil then
		upcoming = rollRarity()
	end
	if only then
		sendScout(only)
		return
	end
	for player in scouts do
		sendScout(player)
	end
end

-- The odds changed (Night Rush or Golden Hour started or ended) since the early roll: it was made with odds the sign no
-- longer shows, so it goes. Every arrival rolls with the odds on the sign at that moment, for everyone, whoever has
-- 🔭 Belt Scout (§E5: one player's perk never changes anyone's odds). The scouts get the fresh roll at once.
local function rescout()
	local ahead = upcoming
	if ahead and ahead.Event ~= Pure.event(nightRush(), golden.Active) then
		upcoming = nil
		if next(scouts) ~= nil then
			scoutAhead(nil)
		end
	end
end

local function arrive(now: number, startAt: number)
	local b = belt :: Belt
	-- A roll made one arrival early (🔭 Belt Scout) is used as it was told, but only while the odds it was rolled with
	-- are still the sign's; otherwise roll with the odds now.
	rescout()
	local roll = upcoming or rollRarity()
	upcoming = nil
	local rarity = roll.Rarity
	local nurseId = BeltLogic.pick(NursesData, rarity, rng:NextNumber())
	if not nurseId then
		rarity = "Common"
		nurseId = BeltLogic.pick(NursesData, rarity, rng:NextNumber())
	end
	local nurse = if nurseId then nurseOf(nurseId) else nil
	if not nurseId or not nurse then
		return
	end
	dry = BeltLogic.afterArrival(dry, rarity)
	Workspace:SetAttribute("BeltPity", BeltLogic.pityLeft(dry, Config))

	lastRiderId += 1
	local id = lastRiderId
	local model = NurseBuilder.build(nurseId)
	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return
	end
	model.Name = "Rider_" .. id
	model:SetAttribute("RiderId", id)
	model:SetAttribute("NurseId", nurseId)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Role", nurse.Role)
	model:SetAttribute("StartAt", startAt)
	model:SetAttribute("RideSeconds", Config.Belt.RideSeconds)
	model:SetAttribute("Hired", false)
	model:SetAttribute("Event", roll.Event)

	local _, size = model:GetBoundingBox()
	local attachment = Instance.new("Attachment")
	attachment.Name = "HireAttachment"
	attachment.Position = Vector3.new(0, size.Y * 0.6, 0)
	attachment.Parent = root
	local info = rarityInfo(rarity)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HirePrompt"
	prompt.ActionText = "Hire"
	prompt.ObjectText = (if info then info.Icon .. " " else "") .. nurse.Name
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.Triggered:Connect(function(player: Player)
		onPrompt(player, id)
	end)
	prompt.Parent = attachment

	local rider: Rider = {
		Id = id,
		NurseId = nurseId,
		Rarity = rarity,
		Model = model,
		Root = root,
		Prompt = prompt,
		StartAt = startAt,
		Ride = Config.Belt.RideSeconds,
		Hired = false,
		Claimed = false,
		Leaving = false,
		SeenBy = {},
	}
	model:PivotTo(formulaCFrame(rider, now))
	if BeltLogic.shouts(rarity) then
		NurseBuilder.setGlow(model, true)
	end
	model.Parent = b.Riders
	riders[id] = rider

	if startAt >= now - 1 then
		pcall(CreatureBuilder.effectAt, b.Start.Position + Vector3.new(0, 1.5, 0), "Pop")
	end
	if BeltLogic.shouts(rarity) then
		Remotes.Shout:FireAllClients({ Kind = "Arrival", RiderId = id, NurseId = nurseId, Rarity = rarity })
	end
	seenBy(rider, now, playerPositions())
	refreshSign()
	-- The pity count is up to date now, so the early roll for the next arrival is exactly the one it would get.
	if next(scouts) ~= nil then
		scoutAhead(nil)
	end
end

local function ridingCount(): number
	local count = 0
	for _, rider in riders do
		if not rider.Leaving then
			count += 1
		end
	end
	return count
end

local function stepRiders(now: number)
	local positions = playerPositions()
	for _, rider in table.clone(riders) do
		if not rider.Leaving then
			if BeltLogic.alpha(rider.StartAt, now, rider.Ride) >= 1 then
				fallOff(rider, now)
			else
				rider.Root.CFrame = formulaCFrame(rider, now)
				seenBy(rider, now, positions)
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Night Rush and Golden Hour
------------------------------------------------------------------------------------------------------------------

local function syncNight()
	local night = nightRush()
	if Workspace:GetAttribute("NightRush") ~= night then
		Workspace:SetAttribute("NightRush", night)
		refreshSign()
		rescout()
	end
end

local function updateGolden(now: number)
	local uptime = now - serverStart
	if forcedFrom and uptime >= forcedFrom + Config.Belt.GoldenSeconds then
		forcedFrom = nil
	end
	local active, startsAt, endsAt = Pure.golden(Config, uptime, forcedFrom)
	startsAt += serverStart
	endsAt += serverStart
	local was = golden
	if active == was.Active and math.abs(startsAt - was.StartsAt) < 0.5 and math.abs(endsAt - was.EndsAt) < 0.5 then
		return
	end
	golden = { Active = active, StartsAt = startsAt, EndsAt = endsAt }
	Workspace:SetAttribute("GoldenStartsAt", startsAt)
	Workspace:SetAttribute("GoldenEndsAt", endsAt)
	Workspace:SetAttribute("GoldenHour", active)
	if active ~= was.Active then
		Remotes.Shout:FireAllClients({
			Kind = "Golden",
			On = active,
			EndsAt = if active then endsAt else was.EndsAt,
		})
		refreshSign()
		rescout()
	end
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

-- The belt model's NextArrivalAt (the house lamp): written only when the time moves by more than 2 s, so a full belt
-- (MaxRiders; the next arrival waits a second at a time) doesn't write it every second. It then stays in the past and
-- the lamp stays bright.
local lastPublished = -math.huge
local function publishNext()
	local b = belt
	if b and math.abs(nextArrival - lastPublished) > 2 then
		lastPublished = nextArrival
		b.Model:SetAttribute(NEXT_ATTRIBUTE, nextArrival)
	end
end

function NurseBelt.goldenHour(): boolean
	return golden.Active
end

function NurseBelt.odds(): { [string]: number }
	return BeltLogic.odds(Config, nightRush(), golden.Active)
end

function NurseBelt.hire(player: Player, riderId: number): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, Remotes.OOPS
	end
	if not belt or type(riderId) ~= "number" then
		return false, Remotes.OOPS
	end
	local rider = riders[riderId]
	if not rider or rider.Leaving then
		return false, if rider and rider.Hired then MSG.Taken else MSG.Gone
	end
	if rider.Hired or rider.Claimed then
		return false, MSG.Taken
	end
	local now = Workspace:GetServerTimeNow()
	local last = lastHire[player]
	if last and now - last < Config.Belt.HireCooldown then
		return false, MSG.Wait
	end
	local root = characterRoot(player)
	if not root then
		return false, Remotes.OOPS
	end
	if BeltLogic.alpha(rider.StartAt, now, rider.Ride) >= 1 then
		return false, MSG.Gone
	end
	if (root.Position - formulaPosition(rider, now)).Magnitude > Config.Belt.HireDistance then
		return false, MSG.Closer
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local level = Levels.level(player)
	-- Epic and up ride for everyone but need hospital Lv 3 to hire (memory-20261116-017), and Mythic and Secret the
	-- first rebirth (design §7); the card already says so ("🏥 Lv 3" / "🏢 R1", never a lock or a price).
	local gate = BeltLogic.gate(Config, rider.Rarity, level, rebirthsOf(data))
	if gate then
		return false, Pure.gateMessage(gate)
	end
	-- Roster room for a new nurse ("Roster full: sell or list one"), or not at the level cap for a copy ("Max
	-- level!"): a clear reply before the grant (which checks it again inside its one update).
	local canAdd, why = NurseLogic.canAdd(data, rider.NurseId, Config, knownNurse)
	if not canAdd then
		return false, why
	end
	local price = Pure.bargainPrice(BeltLogic.price(Config, rider.Rarity, level), effectsOf(data).Bargain)

	rider.Claimed = true
	local ok, granted, message = pcall(Nurses.grant, player, rider.NurseId, price, "Belt")
	if not ok or granted ~= true then
		rider.Claimed = false
		if not ok then
			report("Nurses.grant", granted)
		end
		return false, if ok and type(message) == "string" then message else Remotes.OOPS
	end
	rider.Hired = true
	lastHire[player] = now
	rider.Model:SetAttribute("Hired", true)
	local others = 0
	for _, other in riders do
		if not other.Leaving and not other.Hired and not other.Claimed then
			others += 1
		end
	end
	nextArrival = Pure.afterHire(nextArrival, now, rider.Rarity, Config, others)
	publishNext()
	if Pure.hiredShout(rider.Rarity) then
		Remotes.Shout:FireAllClients({
			Kind = "Hired",
			NurseId = rider.NurseId,
			Rarity = rider.Rarity,
			By = player.DisplayName,
		})
	end
	leaveHired(rider, player, now)
	return true, if type(message) == "string" then message else ""
end

local function tick()
	local now = Workspace:GetServerTimeNow()
	updateGolden(now)
	if now >= nextArrival then
		if ridingCount() < Config.Belt.MaxRiders then
			nextArrival = now + Config.Belt.ArriveSeconds -- first, so an arrival that errors waits its turn
			arrive(now, now)
		else
			nextArrival = now + 1
		end
		publishNext()
	end
	if now >= nextStep then
		nextStep = now + Config.Belt.ServerStepSeconds
		stepRiders(now)
	end
end

function NurseBelt.start()
	Remotes.serve("HireNurse", function(player: Player, riderId: any)
		if type(riderId) ~= "number" or riderId ~= riderId or riderId % 1 ~= 0 then
			return false, Remotes.OOPS
		end
		return NurseBelt.hire(player, riderId)
	end)

	-- The belt's frame: its start on the street, its +X turned by Heading (180: riders move west).
	local town = Config.Town.Origin
	local origin = town + Config.Belt.Offset
	local ground = streetTop()
	local heading = math.rad(tonumber((Config.Belt :: any).Heading) or 0)
	local frame = CFrame.new(origin.X, ground, origin.Z) * CFrame.Angles(0, heading, 0)
	local old = Workspace:FindFirstChild(MODEL_NAME)
	if old then
		warn("[NurseBelt] Replacing an existing Workspace." .. MODEL_NAME)
		old:Destroy()
	end
	local model = kitBelt(frame) or placeholderBelt(frame)
	-- TownSpawn (the plaza's middle): the sign and the riders turn to it.
	-- The real TownSpawn when the place has one (like Market and Agency), else where TownBuilder puts it.
	local townSpawn = Workspace:FindFirstChild("TownSpawn")
	local spawnAt = if townSpawn and townSpawn:IsA("BasePart")
		then Vector3.new(townSpawn.Position.X, town.Y, townSpawn.Position.Z)
		else town + Config.Town.SpawnOffset
	if not model:FindFirstChild("Sign") then
		-- The placeholder's odds sign: at the plaza's west end (Config.Belt.SignOffset), facing TownSpawn.
		local offset = (Config.Belt :: any).SignOffset
		local at = if typeof(offset) == "Vector3" then town + offset else origin
		local foot = Vector3.new(at.X, ground, at.Z)
		local fx, fz = Pure.toward(at.X, at.Z, spawnAt.X, spawnAt.Z, -frame.XVector.X, -frame.XVector.Z)
		buildSignStand(model, CFrame.lookAt(foot, foot + Vector3.new(fx, 0, fz)))
	end
	local start = model:FindFirstChild("BeltStart") :: BasePart
	local finish = model:FindFirstChild("BeltEnd") :: BasePart
	local along = finish.Position - start.Position
	local dir = Vector3.new(along.X, 0, along.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.xAxis
	-- Riders face the plaza (memory-20261117-001 #3: the belt runs down the centre line, the plaza and the spawn are on
	-- the street's row-2 half): across the belt, toward TownSpawn.
	local faceX, faceZ = Pure.riderFacing(dir.X, dir.Z, start.Position.X, start.Position.Z, spawnAt.X, spawnAt.Z)
	local facing = Vector3.new(faceX, 0, faceZ)
	local b: Belt = {
		Model = model,
		Start = start,
		End = finish,
		Riders = model:FindFirstChild("Riders") :: Instance,
		GroundY = frame.Y,
		Dir = dir,
		Side = dir:Cross(Vector3.yAxis).Unit,
		Facing = CFrame.lookAt(Vector3.zero, facing).Rotation,
		Sign = nil,
	}
	local sign = model:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		b.Sign = buildSign(sign)
		addOddsPrompt(sign)
	end
	if not model:FindFirstChild(LAMP_NAME) then
		-- A kit belt without the "next nurse" lamp gets one above where riders step on, a little back toward the house.
		addLamp(model, CFrame.new(start.Position + Vector3.new(0, 4.5, 0) - dir * 1.5))
	end
	belt = b
	model.Parent = Workspace

	Workspace:SetAttribute("BeltPity", BeltLogic.pityLeft(dry, Config))
	syncNight()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(syncNight)
	Workspace:GetAttributeChangedSignal("ForceGolden"):Connect(function()
		if RunService:IsStudio() and Workspace:GetAttribute("ForceGolden") == true then
			forcedFrom = Workspace:GetServerTimeNow() - serverStart
			Workspace:SetAttribute("ForceGolden", nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHire[player] = nil
		scouts[player] = nil
	end)
	-- 🔭 Belt Scout owners: on every save change (a join's load, a perk chosen), cheap (the perks and the tree only).
	-- A new owner gets the next arrival's rarity at once (rolled now if nobody had it rolled yet).
	local function syncScout(player: Player, data: any)
		if player.Parent ~= Players then
			scouts[player] = nil
			return
		end
		local ok, has = pcall(function()
			return effectsOf(data).BeltScout
		end)
		if not ok then
			report("the Belt Scout check", has)
			return
		end
		if has and not scouts[player] then
			scouts[player] = true
			scoutAhead(player)
		elseif not has and scouts[player] then
			scouts[player] = nil
		end
	end
	PlayerData.Changed:Connect(syncScout)

	local now = Workspace:GetServerTimeNow()
	updateGolden(now)
	for k = PREFILL, 1, -1 do
		local ok, err = pcall(arrive, now, now - k * Config.Belt.ArriveSeconds)
		if not ok then
			report("an arrival", err)
		end
	end
	nextArrival = now
	publishNext()
	refreshSign()
	for _, player in Players:GetPlayers() do -- owners loaded before the belt started (after its first riders)
		local data = PlayerData.get(player)
		if data then
			syncScout(player, data)
		end
	end

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				report("the belt", err)
			end
			task.wait(TICK)
		end
	end)
end

return NurseBelt
