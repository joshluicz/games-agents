--!strict
-- The Nurse Agency kiosk: restocks, buys and the sell-back (Progression v2 build plan §B3.1/§B4/§B8; design §8,
-- memory-20261116-018). Server only. OWNER: T3. The rules are Logic/Agency (Lune-tested) and the checks below (the
-- PURE block, tests/AgencyServer.spec). Cash only, no Robux anywhere (red line 3). No countdown anywhere (§E9): the
-- kiosk and the panel say "🔄 New nurses every 5 min". The odds are on show (AgencyView.Odds is the very table the
-- rolls use), and the client asks before every buy and sell.
--
--   Agency.start()
--       builds the kiosk Workspace.NurseAgency (Config.Town.Origin + Config.Agency.Offset, the plaza's row-2 side,
--       facing the spawn; a ServerStorage.ClinicKit.NurseAgency Model replaces the placeholder). Its ProximityPrompt
--       "Prompt" (ActionText "Agency") opens the panel on the client. Serves GetAgency, AgencyBuy and SellNurse,
--       and runs the restock clock: every Config.Agency.RestockSeconds of server uptime a new stock of
--       Config.Agency.Slots distinct nurses (Logic/Agency.roll with the server's Random), the Workspace attribute
--       AgencyRestock (the restock index) and an AgencyNews to every player.
--   Agency.view(p): AgencyView
--       what this player sees now: the shared stock, plus 🍀 Lucky Stock's Config.Agency.LuckySlots own slots
--       (Logic/Agency.personal, seeded by (UserId, restock), so asking again or rejoining never re-rolls them, with
--       the shown odds kept exact even when the shared stock holds every nurse of a rarity), each
--       with YOUR price (Logic/Agency.price at your hospital level, 🏷️ Bargain off), whether you bought it this
--       restock, its gate ("🏥 Lv 3" | "🏢 R1"), the odds and what the Agency pays for each nurse you own
--   Agency.buy(p, slot, nurseId, expect): (ok, message, view?)
--       §B3.1 in order (Pure.checkBuy): the slot is in your view for this restock · it holds nurseId (else "New
--       nurses came! Look again" and a fresh AgencyNews) · not bought by you this restock (in memory by UserId) ·
--       the gates · Logic/Nurse.canAdd · expect == your price (else "Price changed! Look again") · the cash ·
--       Config.Agency.Cooldown per player. Then the slot is claimed (a second call waits it out), Nurses.grant(..,
--       "Agency") charges and adds the copy in ONE update, and the slot is marked bought only after a true.
--   Agency.sell(p, nurseId, expect): (ok, message, view?)
--       §B3.1 in order (Pure.checkSell): you own it · it isn't listed on the Market (Nurses.isListed: "🏷️ Unlist it
--       first!") · it isn't rebirth-only ("This one stays with you!") · expect == Logic/Agency.sellBack (30% of the
--       belt's base price per copy) · the cooldown. Then Nurses.take(.., "Sold"): the nurse goes and the cash comes in
--       ONE update. The Journal keeps "Hired".
--   Agency.restockNow(): (ok, message)   Admin "RefillAgency": a new stock now (it counts as a new restock index)
--   Agency.Pure                          the pure helpers between the PURE markers (tests/AgencyServer.spec)
-- Every reply is a message of 6 words or fewer; buy and sell also pass the fresh view back (Remotes.serve's payload).
-- Requires Nurses, PlayerData and Levels; never Market. No module requires Agency (but Admin).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local AgencyLogic = require(Shared.Logic.Agency)
local BeltLogic = require(Shared.Logic.Belt)
local NurseLogic = require(Shared.Logic.Nurse)
local RebirthLogic = require(Shared.Logic.Rebirth)
local NursesData = require(Shared.Data.Nurses)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local Levels = require(script.Parent.Levels)
local Nurses = require(script.Parent.Nurses)
local PlayerData = require(script.Parent.PlayerData)

local Agency = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services; the only upvalues are Logic/Agency, Logic/Belt and Logic/Nurse as AgencyLogic,
-- BeltLogic and NurseLogic: tests/AgencyServer.spec loads this block on its own with those)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

-- Replies (6 words or fewer)
Pure.MSG = {
	Oops = "Oops! Try again.",
	Restocked = "New nurses came! Look again",
	Bought = "✅ You bought this one!",
	Price = "Price changed! Look again",
	Wait = "Wait a moment! ⏳",
	NotYours = "That nurse isn't yours!",
	Listed = "🏷️ Unlist it first!",
	Stays = "This one stays with you!",
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Pure.isWhole(value: any): boolean
	return finite(value) and value % 1 == 0
end

-- 12345 -> "12,345"
function Pure.commas(n: number): string
	local digits = tostring(math.floor(math.abs(if finite(n) then n else 0)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- The kiosk's and the panel's line: how often new nurses come, never a clock (§E9). "🔄 New nurses every 5 min".
function Pure.everyText(seconds: any): string
	local s = if finite(seconds) then math.max(1, math.floor(seconds + 0.5)) else 300
	if s % 60 == 0 then
		return "🔄 New nurses every " .. tostring(s // 60) .. " min"
	end
	return "🔄 New nurses every " .. tostring(s) .. " s"
end

-- The bought and in-flight marks, in memory by UserId (a rejoin to this server remembers them). Keys are
-- "<restock>:<slot>", so a buy that finishes after a restock never marks the new stock's slot.
export type Ledger = { Bought: { [number]: { [string]: boolean } }, Busy: { [number]: { [string]: boolean } } }

function Pure.ledger(): Ledger
	return { Bought = {}, Busy = {} }
end

function Pure.key(restock: number, slot: number): string
	return tostring(restock) .. ":" .. tostring(slot)
end

local function marks(map: { [number]: { [string]: boolean } }, userId: number): { [string]: boolean }
	local set = map[userId]
	if not set then
		set = {}
		map[userId] = set
	end
	return set
end

function Pure.isBought(ledger: Ledger, userId: number, restock: number, slot: number): boolean
	local set = ledger.Bought[userId]
	return set ~= nil and set[Pure.key(restock, slot)] == true
end

function Pure.markBought(ledger: Ledger, userId: number, restock: number, slot: number)
	marks(ledger.Bought, userId)[Pure.key(restock, slot)] = true
end

function Pure.isBusy(ledger: Ledger, userId: number, restock: number, slot: number): boolean
	local set = ledger.Busy[userId]
	return set ~= nil and set[Pure.key(restock, slot)] == true
end

function Pure.setBusy(ledger: Ledger, userId: number, restock: number, slot: number, on: boolean)
	marks(ledger.Busy, userId)[Pure.key(restock, slot)] = if on then true else nil
end

-- A new restock: every mark of an older one goes (the in-flight ones too: their grant, if it lands, marks the old key).
function Pure.prune(ledger: Ledger, restock: number)
	local prefix = tostring(restock) .. ":"
	for _, map in { ledger.Bought, ledger.Busy } do
		for userId, set in map do
			for key in set do
				if string.sub(key, 1, #prefix) ~= prefix then
					set[key] = nil
				end
			end
			if next(set) == nil then
				map[userId] = nil
			end
		end
	end
end

-- The view one player sees (Types.AgencyView). `input`:
--   Restock (the index) · Stock (the shared nurses) · Lucky (this player's 🍀 nurses, or {}) · Roster (Data/Nurses)
--   · Cfg · Level (hospital) · Rebirths · Bargain (fraction off) · Nurses (the save's) · Bought (slot) -> boolean
-- Slots are numbered in order: the shared stock first (1..), then the Lucky Stock ones (Personal = true).
function Pure.view(input: any): any
	local cfg = input.Cfg
	local roster = input.Roster
	local slots = {}
	local slot = 0
	local function add(nurseId: string, personal: boolean)
		slot += 1
		local nurse = if type(nurseId) == "string" then rawget(roster, nurseId) else nil
		if type(nurse) ~= "table" then
			return -- never happens (rolls pick from the roster); the numbering stays put anyway
		end
		table.insert(slots, {
			Slot = slot,
			NurseId = nurseId,
			Rarity = nurse.Rarity,
			Price = AgencyLogic.price(cfg, nurse.Rarity, input.Level, input.Bargain),
			Bought = input.Bought(slot) == true,
			Personal = personal,
			Gate = BeltLogic.gate(cfg, nurse.Rarity, input.Level, input.Rebirths),
		})
	end
	for _, nurseId in input.Stock do
		add(nurseId, false)
	end
	for _, nurseId in input.Lucky do
		add(nurseId, true)
	end
	local sellBack: { [string]: number } = {}
	if type(input.Nurses) == "table" then
		for nurseId, entry in input.Nurses do
			local nurse = if type(nurseId) == "string" then rawget(roster, nurseId) else nil
			if type(nurse) == "table" and nurse.Source == nil and type(entry) == "table" then
				sellBack[nurseId] = AgencyLogic.sellBack(entry, nurse.Rarity, cfg)
			end
		end
	end
	return { Restock = input.Restock, Slots = slots, Odds = AgencyLogic.odds(cfg), SellBack = sellBack }
end

-- 🍀 Lucky Stock: Config.Agency.LuckySlots nurses of your own this restock: Logic/Agency.personal (seeded by
-- (userId, restock), so asking again or rejoining never re-rolls them, and it uses nothing the player can change).
-- Each slot's rarity is rolled with exactly the shown odds; a nurse is never repeated among your own slots and avoids
-- the shared stock, and only when every nurse of the rolled rarity is already in the shared stock does a slot repeat
-- one of those, so the odds on show stay true (T3's rule, moved into Logic at integration: tests/AgencyServer.spec).
function Pure.lucky(roster: any, cfg: any, userId: number, restock: number, shared: { string }): { string }
	return AgencyLogic.personal(roster, cfg, userId, restock, shared)
end

function Pure.findSlot(view: any, slot: number): any
	for _, row in view.Slots do
		if row.Slot == slot then
			return row
		end
	end
	return nil
end

-- AgencyBuy's checks, in §B3.1's order. `input`:
--   View (Pure.view for the CURRENT restock) · Slot · NurseId · Expect (all untrusted) · Data (the save) · Cfg ·
--   IsKnown (nurseId) -> boolean · Busy (this slot's buy is in flight) · Now · Last (the last buy or sell, or nil)
-- Returns (ok, message, price, refresh): refresh = the client's view is stale, so send it a fresh AgencyNews.
function Pure.checkBuy(input: any): (boolean, string, number, boolean)
	local MSG = Pure.MSG
	local slot, nurseId = input.Slot, input.NurseId
	-- 1. a whole number, and that slot exists in your view for the current restock
	if not Pure.isWhole(slot) or type(nurseId) ~= "string" then
		return false, MSG.Oops, 0, false
	end
	local row = Pure.findSlot(input.View, slot)
	if not row then
		return false, MSG.Restocked, 0, true
	end
	-- 2. the nurse the client saw is the one there now
	if row.NurseId ~= nurseId then
		return false, MSG.Restocked, 0, true
	end
	-- 3. once per restock (and not while your other buy of it is in flight)
	if row.Bought then
		return false, MSG.Bought, 0, false
	end
	if input.Busy then
		return false, MSG.Wait, 0, false
	end
	-- 4. the gates (the belt's: hospital level, rebirths)
	if type(row.Gate) == "string" then
		return false, row.Gate .. " first!", 0, false
	end
	-- 5. roster room for a new nurse, or not at the level cap for a copy
	local data = input.Data
	local canAdd, why = NurseLogic.canAdd(data, nurseId, input.Cfg, input.IsKnown)
	if not canAdd then
		return false, why, 0, false
	end
	-- 6. the price the client saw is the price now
	if not finite(input.Expect) or input.Expect ~= row.Price then
		return false, MSG.Price, 0, true
	end
	-- 7. the cash
	local cash = if type(data) == "table" and finite(data.Cash) then data.Cash else 0
	if cash < row.Price then
		return false, "Need 💰" .. Pure.commas(row.Price - cash) .. " more!", 0, false
	end
	-- 8. the cooldown
	local agency = if type(input.Cfg) == "table" and type(input.Cfg.Agency) == "table" then input.Cfg.Agency else {}
	local cooldown = if finite(agency.Cooldown) then agency.Cooldown else 1
	if finite(input.Last) and finite(input.Now) and input.Now - input.Last < cooldown then
		return false, MSG.Wait, 0, false
	end
	return true, "", row.Price, false
end

-- SellNurse's checks, in §B3.1's order. `input`:
--   Data (the save) · NurseId · Expect (untrusted) · Listed (Nurses.isListed) · Roster (Data/Nurses) · Cfg · Now ·
--   Last
-- Returns (ok, message, cash, refresh).
function Pure.checkSell(input: any): (boolean, string, number, boolean)
	local MSG = Pure.MSG
	local nurseId = input.NurseId
	if type(nurseId) ~= "string" then
		return false, MSG.Oops, 0, false
	end
	-- 1. you own it (a nurse this game knows)
	local nurse = rawget(input.Roster, nurseId)
	local nurses = if type(input.Data) == "table" then input.Data.Nurses else nil
	local entry = if type(nurses) == "table" then nurses[nurseId] else nil
	if type(nurse) ~= "table" or type(entry) ~= "table" then
		return false, MSG.NotYours, 0, false
	end
	-- 2. not while it's listed on the Market
	if input.Listed then
		return false, MSG.Listed, 0, false
	end
	-- 3. rebirth-only nurses can't be sold
	if nurse.Source ~= nil then
		return false, MSG.Stays, 0, false
	end
	-- 4. the price the client saw
	local cash = AgencyLogic.sellBack(entry, nurse.Rarity, input.Cfg)
	if not finite(input.Expect) or input.Expect ~= cash then
		return false, MSG.Price, 0, true
	end
	-- 5. the cooldown
	local agency = if type(input.Cfg) == "table" and type(input.Cfg.Agency) == "table" then input.Cfg.Agency else {}
	local cooldown = if finite(agency.Cooldown) then agency.Cooldown else 1
	if finite(input.Last) and finite(input.Now) and input.Now - input.Last < cooldown then
		return false, MSG.Wait, 0, false
	end
	return true, "", cash, false
end
-- PURE-END

Agency.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------------------------

local MODEL_NAME = "NurseAgency"
local TICK = 1 -- the restock clock is checked this often
local MAX_ID_LENGTH = 40
local PROMPT_DISTANCE = 10
local SIGN_PIXELS_PER_STUD = 40

type Stock = { Index: number, Nurses: { string } }

local ledger = Pure.ledger()
local stock: Stock = { Index = -1, Nurses = {} }
local announced = -1 -- the restock every player has been told about
local extraRestocks = 0 -- Admin RefillAgency
local lastAction: { [number]: number } = {} -- UserId -> os.clock() of the last buy or sell
local rng = Random.new()
local failures: { [string]: number } = {}

local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Agency] " .. label .. " failed: " .. tostring(err))
	end
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function knownNurse(nurseId: string): boolean
	return type(nurseId) == "string" and type(rawget(NursesData :: any, nurseId)) == "table"
end

local function rebirthsOf(data: any): number
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	return if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
end

local function effectsOf(data: any): RebirthLogic.Effects
	return RebirthLogic.effects(data, Config, PerksData, TreeData)
end

------------------------------------------------------------------------------------------------------------------
-- The stock
------------------------------------------------------------------------------------------------------------------

local function currentIndex(): number
	return AgencyLogic.restock(time(), Config) + extraRestocks
end

local function rollStock(index: number)
	local r01s: { number } = {}
	for i = 1, math.max(0, Config.Agency.Slots) * 2 do
		r01s[i] = rng:NextNumber()
	end
	stock = { Index = index, Nurses = AgencyLogic.roll(NursesData, Config, r01s) }
	Pure.prune(ledger, index)
	Workspace:SetAttribute("AgencyRestock", index)
end

local function ensureStock()
	local index = currentIndex()
	if index ~= stock.Index then
		rollStock(index)
	end
end

local function viewFor(player: Player, data: Types.Data): Types.AgencyView
	ensureStock()
	local userId = player.UserId
	local index = stock.Index
	local effects = effectsOf(data)
	local lucky = if effects.LuckyStock
		then AgencyLogic.personal(NursesData, Config, userId, index, stock.Nurses)
		else {}
	return Pure.view({
		Restock = index,
		Stock = stock.Nurses,
		Lucky = lucky,
		Roster = NursesData,
		Cfg = Config,
		Level = Levels.level(player),
		Rebirths = rebirthsOf(data),
		Bargain = effects.Bargain,
		Nurses = data.Nurses,
		Bought = function(slot: number): boolean
			return Pure.isBought(ledger, userId, index, slot)
		end,
	})
end

local function emptyView(): Types.AgencyView
	return { Restock = math.max(0, stock.Index), Slots = {}, Odds = AgencyLogic.odds(Config), SellBack = {} }
end

local function push(player: Player)
	if player.Parent ~= Players then
		return
	end
	local data = PlayerData.get(player)
	if data then
		Remotes.AgencyNews:FireClient(player, viewFor(player, data))
	end
end

local function announce()
	announced = stock.Index
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(push, player)
		if not ok then
			report("AgencyNews", err)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- The kiosk (≤ 25 parts, no Highlight, no shadow-casting light)
------------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, solid: boolean): Part
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
	p.CanCollide = solid
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3): Part
	local p = part(parent, name, Vector3.one * diameter, cf, color, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function signLabel(parent: Instance, name: string, text: string, y: number, height: number, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(0.92, height)
	label.Font = Palette.DisplayFont
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	Palette.outlineText(label, 2)
	label.Parent = parent
end

local function buildSign(sign: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AgencyGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	signLabel(gui, "Title", "🏢 Nurse Agency", 0.06, 0.52, Palette.White)
	signLabel(gui, "Every", Pure.everyText(Config.Agency.RestockSeconds), 0.6, 0.32, Palette.Candy.Yellow)
	gui.Parent = sign
end

local function addPrompt(parent: BasePart): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Agency"
	prompt.ObjectText = "🏢 Nurses"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

-- A candy booth: a counter under a striped awning with the sign on top. `frame` is the ground under its middle,
-- its LookVector toward the spawn (the counter's front).
local function placeholderKiosk(frame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	local candy = Palette.Candy
	local white = Palette.White
	local width, depth = 7, 4.5
	part(model, "Base", Vector3.new(width, 0.4, depth), frame * CFrame.new(0, 0.2, 0), white, true)
	part(model, "BackWall", Vector3.new(width, 6, 0.4), frame * CFrame.new(0, 3.4, depth / 2 - 0.2), candy.Cyan, true)
	part(model, "Counter", Vector3.new(width - 1, 2.6, 1.2), frame * CFrame.new(0, 1.7, -1.1), white, true)
	part(
		model,
		"CounterStripe",
		Vector3.new(width - 0.95, 0.5, 1.25),
		frame * CFrame.new(0, 2.5, -1.1),
		candy.Pink,
		false
	)
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 0.35)
		part(model, "Post", Vector3.new(0.5, 6.6, 0.5), frame * CFrame.new(x, 3.7, -(depth / 2 - 0.35)), white, true)
		ball(model, "PostCap", 0.9, frame * CFrame.new(x, 7.15, -(depth / 2 - 0.35)), candy.Yellow)
	end
	part(model, "Awning", Vector3.new(width + 0.6, 0.5, depth + 0.4), frame * CFrame.new(0, 7.2, 0), candy.Cyan, false)
	part(
		model,
		"AwningStripe",
		Vector3.new(width + 0.65, 0.25, depth + 0.45),
		frame * CFrame.new(0, 6.95, 0),
		white,
		false
	)
	for i = 1, 4 do
		local x = (i - 2.5) * (width / 4)
		ball(
			model,
			"Scallop",
			1.1,
			frame * CFrame.new(x, 6.85, -(depth / 2 + 0.15)),
			if i % 2 == 0 then white else candy.Pink
		)
	end
	local sign =
		part(model, "Sign", Vector3.new(width - 0.6, 2, 0.3), frame * CFrame.new(0, 8.5, -1.4), candy.Pink, false)
	buildSign(sign)
	local promptPart =
		part(model, "PromptPart", Vector3.new(1, 1, 1), frame * CFrame.new(0, 2.6, -(depth / 2 + 0.6)), white, false)
	promptPart.Transparency = 1
	promptPart.CanQuery = false
	promptPart.CanTouch = false
	addPrompt(promptPart)
	model.WorldPivot = frame
	return model
end

-- The brother's kiosk (ServerStorage.ClinicKit.NurseAgency): no scripts, no Highlights, no shadows, and a Prompt.
local function kitKiosk(frame: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild(MODEL_NAME)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	local firstPart: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			warn("[Agency] Removed a script from ClinicKit.NurseAgency:", descendant:GetFullName())
			descendant:Destroy()
		elseif descendant:IsA("Highlight") then
			descendant:Destroy()
		elseif descendant:IsA("Light") then
			descendant.Shadows = false
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			firstPart = firstPart or descendant
		end
	end
	model.Name = MODEL_NAME
	model:PivotTo(frame)
	local prompt = model:FindFirstChild("Prompt", true)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		local holder = model.PrimaryPart or firstPart
		if not holder then
			warn("[Agency] ClinicKit.NurseAgency has no parts; using the placeholder")
			model:Destroy()
			return nil
		end
		addPrompt(holder)
	end
	return model
end

local function groundY(at: Vector3): number
	local town = Workspace:FindFirstChild("ClinicTown")
	if town then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { town }
		local hit = Workspace:Raycast(Vector3.new(at.X, at.Y + 30, at.Z), Vector3.new(0, -60, 0), params)
		if hit then
			return hit.Position.Y
		end
	end
	return at.Y + 0.5
end

local function buildKiosk()
	local origin = Config.Town.Origin
	local at = origin + Config.Agency.Offset
	local foot = Vector3.new(at.X, groundY(at), at.Z)
	local spawn = Workspace:FindFirstChild("TownSpawn")
	local target = if spawn and spawn:IsA("BasePart") then spawn.Position else origin
	local toward = Vector3.new(target.X - foot.X, 0, target.Z - foot.Z)
	local face = if toward.Magnitude > 0.5 then toward.Unit else -Vector3.zAxis
	local frame = CFrame.lookAt(foot, foot + face)
	local old = Workspace:FindFirstChild(MODEL_NAME)
	if old then
		warn("[Agency] Replacing an existing Workspace." .. MODEL_NAME)
		old:Destroy()
	end
	local model = kitKiosk(frame) or placeholderKiosk(frame)
	model.Parent = Workspace
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Agency.view(player: Player): Types.AgencyView
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	if not data then
		ensureStock()
		return emptyView()
	end
	return viewFor(player, data)
end

function Agency.buy(player: Player, slot: number, nurseId: string, expect: number): (boolean, string, any)
	if not isPlayer(player) or player.Parent ~= Players then
		return false, Pure.MSG.Oops, nil
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Pure.MSG.Oops, nil
	end
	local view = viewFor(player, data)
	local userId = player.UserId
	local index = view.Restock
	local busy = Pure.isWhole(slot) and Pure.isBusy(ledger, userId, index, slot)
	local ok, message, price, refresh = Pure.checkBuy({
		View = view,
		Slot = slot,
		NurseId = nurseId,
		Expect = expect,
		Data = data,
		Cfg = Config,
		IsKnown = knownNurse,
		Busy = busy,
		Now = os.clock(),
		Last = lastAction[userId],
	})
	if not ok then
		if refresh then
			Remotes.AgencyNews:FireClient(player, view)
		end
		return false, message, if refresh then view else nil
	end

	-- Claim the slot before the grant (a second call finds it busy, even if the grant ever yields), charge and add the
	-- copy in ONE update (Nurses.grant), then mark it bought only after a true, with no yield in between.
	lastAction[userId] = os.clock()
	Pure.setBusy(ledger, userId, index, slot, true)
	local called, granted, why = pcall(Nurses.grant, player, nurseId, price, "Agency")
	if called and granted == true then
		Pure.markBought(ledger, userId, index, slot)
	end
	Pure.setBusy(ledger, userId, index, slot, false)
	if not called then
		report("Nurses.grant", granted)
		return false, Pure.MSG.Oops, nil
	end
	if granted ~= true then
		return false, if type(why) == "string" and why ~= "" then why else Pure.MSG.Oops, nil
	end
	local fresh = viewFor(player, PlayerData.get(player) or data)
	Remotes.AgencyNews:FireClient(player, fresh)
	return true, if type(why) == "string" then why else "", fresh
end

function Agency.sell(player: Player, nurseId: string, expect: number): (boolean, string, any)
	if not isPlayer(player) or player.Parent ~= Players then
		return false, Pure.MSG.Oops, nil
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Pure.MSG.Oops, nil
	end
	local listed = false
	if type(nurseId) == "string" then
		local called, result = pcall(Nurses.isListed, player, nurseId)
		if not called then
			report("Nurses.isListed", result)
			return false, Pure.MSG.Oops, nil
		end
		listed = result == true
	end
	local userId = player.UserId
	local ok, message, cash, refresh = Pure.checkSell({
		Data = data,
		NurseId = nurseId,
		Expect = expect,
		Listed = listed,
		Roster = NursesData,
		Cfg = Config,
		Now = os.clock(),
		Last = lastAction[userId],
	})
	if not ok then
		if refresh then
			local view = viewFor(player, data)
			Remotes.AgencyNews:FireClient(player, view)
			return false, message, view
		end
		return false, message, nil
	end

	-- The nurse goes and the cash comes in ONE update (Nurses.take; it refuses a listed or rebirth-only nurse too).
	lastAction[userId] = os.clock()
	local called, taken, why = pcall(Nurses.take, player, nurseId, cash, "Sold")
	if not called then
		report("Nurses.take", taken)
		return false, Pure.MSG.Oops, nil
	end
	if taken ~= true then
		return false, if type(why) == "string" and why ~= "" then why else Pure.MSG.Oops, nil
	end
	local fresh = viewFor(player, PlayerData.get(player) or data)
	Remotes.AgencyNews:FireClient(player, fresh)
	local nurse = rawget(NursesData :: any, nurseId)
	return true, "💰 Sold " .. (if type(nurse) == "table" then nurse.Name else "it") .. "!", fresh
end

function Agency.restockNow(): (boolean, string)
	extraRestocks += 1
	ensureStock()
	announce()
	return true, "🏢 New nurses at the Agency!"
end

function Agency.start()
	Remotes.serve("GetAgency", function(player: Player)
		return true, "", Agency.view(player)
	end)
	Remotes.serve("AgencyBuy", function(player: Player, slot: any, nurseId: any, expect: any)
		if
			type(slot) ~= "number"
			or type(nurseId) ~= "string"
			or #nurseId > MAX_ID_LENGTH
			or type(expect) ~= "number"
		then
			return false, Pure.MSG.Oops
		end
		return Agency.buy(player, slot, nurseId, expect)
	end)
	Remotes.serve("SellNurse", function(player: Player, nurseId: any, expect: any)
		if type(nurseId) ~= "string" or #nurseId > MAX_ID_LENGTH or type(expect) ~= "number" then
			return false, Pure.MSG.Oops
		end
		return Agency.sell(player, nurseId, expect)
	end)

	local built, err = pcall(buildKiosk)
	if not built then
		report("the kiosk", err)
	end

	ensureStock()
	announced = stock.Index
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAction[player.UserId] = nil -- the bought marks stay: a rejoin to this server remembers them
	end)
	task.spawn(function()
		while true do
			local ok, loopErr = pcall(function()
				ensureStock()
				if stock.Index ~= announced then
					announce()
				end
			end)
			if not ok then
				report("the restock clock", loopErr)
			end
			task.wait(TICK)
		end
	end)
end

return Agency
