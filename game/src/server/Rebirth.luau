--!strict
-- Rebirths: "🏢 Open a new branch" (Progression v2 build plan §B3/§B4/§B8; design §7/§8, memory-20261116-017/-019).
-- Server only. OWNER: T2. The rules are Logic/Rebirth and Logic/Tree (Lune-tested); the content is Data/Perks,
-- Data/Tree and Data/Themes. Optional and never pushed (red line 3): one gentle toast ever, no dots, no repeats, no
-- clocks, and no Robux anywhere. The keep/reset screen (Client/UI/BranchPanel) asks OpenBranch(true) only after a
-- hold; "Not now" is its default.
--
--   Rebirth.start()                 wires OpenBranch, ChoosePerk, BuyNode, ResetTree, SetTheme and ClaimBranchNurse;
--                                   keeps each owned plot's Branches attribute (0 on a free plot), its sign's
--                                   BranchBadge ("🏢 n" from R1) and its mascot (R5+) in step with the owner's save;
--                                   sets the player's WalkBoost attribute (🌳 Quick Feet ranks) and Humanoid.WalkSpeed
--                                   = StarterPlayer.CharacterWalkSpeed (16) + WalkBoost on every CharacterAdded and
--                                   tree change; the once-ever Told toast "🏢 You can open a branch!" the first time
--                                   Logic/Rebirth.canRebirth turns true (after the tutorial)
--   Rebirth.count(p): number        the player's Rebirth.Count (0 until their data loads)
--   Rebirth.effects(p): Effects     Logic/Rebirth.effects on the live save (neutral until it loads)
--   Rebirth.open(p, free?): (ok, message)
--       1. the §B3 OpenBranch checks, in order: loaded · PlayerData.canSave ("⚠️ Saving is off") · the tutorial done ·
--          no perk card still waiting ("🃏 Pick your card first!": every rebirth gives exactly one card) ·
--          Logic/Rebirth.canRebirth (Lv 5, cash >= cost) · no treat session open (Treatment.busy) · one rebirth at a
--          time per player ("One at a time!") · 5 s per player. `free` (the admin hook) skips the save, tutorial,
--          card, level, cost and cooldown checks, never the in-flight lock or the count check
--       2. Patients.reopen(p): a treated patient cures on the spot first (its cash lands before the reset)
--       3. the checks again; from here nothing yields until the save has changed
--       4. ONE PlayerData.update: the count it read must still be the count (else nothing), then Logic/Rebirth.apply
--          (with an offer of 3 perk cards rolled by the server's Random, so rejoining never re-rolls it) on a trial
--          copy of the save (Pure.atomic), written back whole or not at all; Rebirth.Told = true
--       5. Plots.syncRooms(p) (the building drops to the Stand by itself: Server/Levels follows Data.Level)
--       6. PlayerData.saveNow(p)
--       7. Celebrate Rebirth, then Unlock per new unlock (a Branch Trophy names its decor); a rebirth-only nurse
--          (FounderFennec at R5) arrives through Nurses.grant(p, id, 0, "Gift") or waits in Rebirth.Pending with the
--          toast "🎁 A nurse waits for a free slot!"; Reborn:Fire(p, count)
--   Rebirth.choose(p, perkId) · Rebirth.buyNode(p, nodeId) · Rebirth.resetTree(p) · Rebirth.setTheme(p, themeId) ·
--   Rebirth.claimNurse(p)           the other remotes' handlers (arguments untrusted), each ONE update:
--       ChoosePerk       perkId in Rebirth.Offer and not in Perks (Logic/Rebirth.choose: a start-of-branch card applies
--                        now; Bath Ready then Plots.syncRooms), Celebrate Perk
--       BuyNode          a Data/Tree node, Logic/Tree.canBuy (points, max rank, a capstone's 6 points in its branch)
--       ResetTree        2 s per player; every rank refunded (Logic/Tree.refund: free, any time)
--       SetTheme         a Data/Themes id unlocked at your Rebirth.Count (Server/Levels redraws the building); 3 s per
--                        player between changes (each one rebuilds the building for everyone)
--       ClaimBranchNurse the first rebirth-only nurse in Rebirth.Pending, through Nurses.grant (roster room; it takes
--                        it out of Pending in the same update)
--   Rebirth.Reborn: Signal (p, count)
--   Rebirth.adminRebirth(p)         Admin "Rebirth": open(p, true) (no Lv 5, no cost)
--   Rebirth.adminPoints(p)          Admin "AddTreePoints": +Config.Rebirth.PointsPerRebirth points
--   Rebirth.Pure                    the pure helpers below (tests/RebirthServer.spec loads the block on its own and
--                                   runs the whole module under mocks)
--
-- The 🏆 Most Rebirths board reads Data.Rebirth.Count straight from the save (Server/Leaderboards, Logic/Leaderboard),
-- so the update above is its feed; the 🏅 Branches badge is derived from the same count (Logic/Badges).
--
-- The mascot (R5, §E19): a small original creature (CreatureBuilder.buildLook; a placeholder look the brothers can
-- replace) standing by the Counter at the plot's MascotSpot (plot-local (-8, 0, -13) without one), facing the street.
-- It never follows anyone. It hops by the creature-motion contract (NurseBuilder.hop: the attributes, then ONE end-pose
-- write per hop, never a per-frame CFrame): a small hop to the side and back every 6-10 s, and a happy spin whenever a
-- patient at its plot is cured (its State attribute turns "Cured"). The clients draw the hops (Feel/CreatureMotion),
-- calm with reduced motion.
--
-- Requires Patients, Treatment, Nurses, Plots, PlayerData (and the builders). No module requires Rebirth (but Admin).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local RebirthLogic = require(Shared.Logic.Rebirth)
local TreeLogic = require(Shared.Logic.Tree)
local TutorialLogic = require(Shared.Logic.Tutorial)
local DecorData = require(Shared.Data.Decor)
local NursesData = require(Shared.Data.Nurses)
local PerksData = require(Shared.Data.Perks)
local ThemesData = require(Shared.Data.Themes)
local TreeData = require(Shared.Data.Tree)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local NurseBuilder = require(script.Parent.NurseBuilder)
local Nurses = require(script.Parent.Nurses)
local Patients = require(script.Parent.Patients)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Treatment = require(script.Parent.Treatment)

type Plot = Types.Plot

-- PURE-BEGIN (tests/RebirthServer.spec loads this block on its own: no Roblox services in here; RebirthLogic and
-- TutorialLogic are the shared Logic modules)
local Pure = {}

-- Replies (on-screen words stay at 6 or fewer).
Pure.MSG = table.freeze({
	Oops = "Oops! Try again.",
	Loading = "Still loading! Try again.",
	SavingOff = "⚠️ Saving is off",
	Tutorial = "Finish the tutorial first!",
	PickCard = "🃏 Pick your card first!",
	Treating = "Finish treating first!",
	Busy = "One at a time!",
	MaxBranches = "🏢 So many branches!",
	Opened = "🏢 New branch open!",
	NotOffered = "🃏 Not one of your cards",
	NothingToReset = "🌳 Nothing to reset!",
	NoGift = "🎁 No gift waiting!",
	AlreadyYours = "🎁 Already yours!",
	GiftWaits = "🎁 A nurse waits for a free slot!", -- the build plan's exact words (§C T2)
	Told = "🏢 You can open a branch!", -- once ever (Rebirth.Told)
})

-- The save fields each write may change. Logic/Rebirth.apply: count, points, offer, theme, pending (Rebirth), cash,
-- upgrades, level, rooms, Decor.Placed and the trophy in Decor.Owned, Stats.RoomsBefore. choose: Rebirth (+ the start
-- card's cash, upgrades, level or room). The tree and the theme: Rebirth only.
Pure.APPLY_KEYS = table.freeze({ "Rebirth", "Cash", "Upgrades", "Level", "Rooms", "Decor", "Stats" })
Pure.CHOOSE_KEYS = table.freeze({ "Rebirth", "Cash", "Upgrades", "Level", "Rooms" })
Pure.REBIRTH_KEYS = table.freeze({ "Rebirth" })

function Pure.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = Pure.deepCopy(item)
	end
	return out
end

-- Writes `value` into data[key]. A table goes into the live table (cleared, then filled), so anything holding the
-- save's sub-table still sees it. Plain assignments: it can't error halfway.
local function commit(data: any, key: string, value: any)
	local current = data[key]
	if type(current) == "table" and type(value) == "table" then
		table.clear(current)
		for k, v in value do
			current[k] = v
		end
	else
		data[key] = value
	end
end

-- Runs fn(trial) on a deep copy of the whole save, then writes back only the listed fields, and only when fn neither
-- errors nor answers false. So a rule that errors halfway (or says no) leaves the save exactly as it was, and a
-- field that isn't listed never changes. Returns (true, fn's result) or (false, its message / the error).
function Pure.atomic(data: any, keys: { string }, fn: (any) -> (boolean, any)): (boolean, any)
	local trial = Pure.deepCopy(data)
	local ran, ok, result = pcall(fn, trial)
	if not ran then
		return false, ok
	end
	if ok ~= true then
		return false, result
	end
	for _, key in keys do
		commit(data, key, trial[key])
	end
	return true, result
end

-- The OpenBranch checks (§B3), in order. view = { Free, CanSave, Treating }: an admin's free rebirth (Free) skips the
-- save, tutorial, card, level and cost checks (Studio FreshSave tests), never the treat session.
function Pure.check(data: any, cfg: any, view: any): (boolean, string)
	if type(data) ~= "table" or type(data.Rebirth) ~= "table" then
		return false, Pure.MSG.Loading
	end
	if not view.Free then
		if not view.CanSave then
			return false, Pure.MSG.SavingOff
		end
		if not TutorialLogic.isDone(data.Tutorial) then
			return false, Pure.MSG.Tutorial
		end
		if type(data.Rebirth.Offer) == "table" and #data.Rebirth.Offer > 0 then
			return false, Pure.MSG.PickCard
		end
		local ok, why = RebirthLogic.canRebirth(data, cfg)
		if not ok then
			return false, why
		end
	end
	if (tonumber(data.Rebirth.Count) or 0) >= RebirthLogic.MAX_COUNT then
		return false, Pure.MSG.MaxBranches
	end
	if view.Treating then
		return false, Pure.MSG.Treating
	end
	return true, ""
end

-- What the Celebrate remote shows after a rebirth, in order: the rebirth, then each unlock new at this count (a Branch
-- Trophy names the decor that landed in Decor.Owned).
function Pure.celebrations(result: any): { any }
	local list: { any } = {
		{ Kind = "Rebirth", Title = "New branch!", Icon = "🏢", Count = result.Count, Theme = result.Theme },
	}
	for _, unlockId in result.Unlocks do
		local info = RebirthLogic.UNLOCKS[unlockId]
		if info then
			local entry: any = { Kind = "Unlock", Title = "Unlocked!", Icon = info.Icon, Unlock = unlockId }
			if string.sub(unlockId, 1, 6) == "Trophy" and type(result.Trophies) == "table" then
				entry.Decor = result.Trophies[1]
			end
			table.insert(list, entry)
		end
	end
	return list
end

-- A chosen card: the Celebrate payload and the reply. The Fallback (🌳 +2 tree points) is perks.Fallback.
local function perkOf(perkId: string, perks: any): any
	if perkId == RebirthLogic.FALLBACK then
		return if type(perks) == "table" then perks.Fallback else nil
	end
	local perk = if type(perks) == "table" then rawget(perks, perkId) else nil
	return if type(perk) == "table" then perk else nil
end

function Pure.perkCelebration(perkId: string, perks: any): any
	local perk = perkOf(perkId, perks)
	return {
		Kind = "Perk",
		Title = if perk then perk.Name else "New card!",
		Icon = if perk then perk.Icon else "🃏",
		Perk = perkId,
	}
end

function Pure.perkReply(perkId: string, perks: any): string
	local perk = perkOf(perkId, perks)
	if not perk then
		return "🃏 Card chosen!"
	end
	if perkId == RebirthLogic.FALLBACK then
		return perk.Icon .. " " .. perk.Text .. "!"
	end
	return perk.Icon .. " " .. perk.Name .. "!"
end

-- A bought node's reply: "👟 Quick Feet 2!" (a capstone has one rank: "👯 Twin Counters!").
function Pure.nodeReply(def: any, rank: number): string
	if def.Capstone == true then
		return def.Icon .. " " .. def.Name .. "!"
	end
	return def.Icon .. " " .. def.Name .. " " .. tostring(rank) .. "!"
end

-- The first nurse in Rebirth.Pending that is a known rebirth-only nurse (`nurses` = Data/Nurses), or nil.
function Pure.firstPending(pending: any, nurses: any): string?
	if type(pending) ~= "table" then
		return nil
	end
	for _, nurseId in ipairs(pending) do
		local nurse = if type(nurseId) == "string" then rawget(nurses, nurseId) else nil
		if type(nurse) == "table" and nurse.Source ~= nil then
			return nurseId
		end
	end
	return nil
end

-- The sign's 🏢 badge: (text, visible). Shown from the first branch.
function Pure.badge(count: number): (string, boolean)
	local n = math.max(0, math.floor(tonumber(count) or 0))
	return "🏢 " .. tostring(n), n >= 1
end

-- Studs a second the 👟 Quick Feet ranks add to the walk speed (Logic/Rebirth.effects(...).Walk).
function Pure.walkBoost(effects: any): number
	local walk = if type(effects) == "table" then tonumber(effects.Walk) else nil
	return math.max(0, walk or 0)
end
-- PURE-END

local MSG = Pure.MSG

local Rebirth = {}

Rebirth.Reborn = Signal.new()
Rebirth.Pure = Pure

local OPEN_COOLDOWN = 5 -- seconds per player between rebirths (§B3)
local RESET_COOLDOWN = 2 -- seconds per player between tree resets (§B3)
-- Seconds per player between theme changes: each change rebuilds the whole hospital building for every client (a
-- client flicking through themes, or a junk one, must not force rebuilds 10 times a second).
local THEME_COOLDOWN = 3
local MAX_ID_LENGTH = 40 -- longer than any id in Shared/Data
local BADGE_NAME = "BranchBadge" -- a TextLabel in the plot's Sign.SignGui (PlotBuilder makes it; added if missing)
local BRANCHES_ATTRIBUTE = "Branches"
local WALK_ATTRIBUTE = "WalkBoost"

local CONTENT = table.freeze({ Perks = PerksData, Themes = ThemesData, Nurses = NursesData, Decor = DecorData })

-- The mascot (an original placeholder look; the brothers may rename or reshape it, OPEN #1).
local MASCOT_NAME = "Mascot"
local MASCOT_LOOK = table.freeze({
	Shape = "Blob",
	Body = "#A8F0DA", -- mint
	Accent = "#FF9CCB", -- candy pink
	Ears = "Round",
	Top = "Bow",
	Extra = "None",
	Scale = 0.6,
})
local MASCOT_SPOT = "MascotSpot" -- PlotBuilder's marker beside the Counter (§B4)
local MASCOT_FALLBACK = { X = -8, Y = 0, Z = -13 } -- plot-local, when the plot has no MascotSpot
local MASCOT_STEP = 1.4 -- studs: its idle hop goes this far to the side and back
local IDLE_MIN, IDLE_MAX = 6, 10 -- seconds between idle hops
local IDLE_HEIGHT, IDLE_SECONDS = 0.9, 0.4
local CHEER_HEIGHT, CHEER_SECONDS = 2.2, 0.6 -- a happy spin on a cure
local POLL_SECONDS = 0.25 -- how soon a cure's spin starts

type Mascot = {
	Plot: Plot,
	Model: Model,
	Home: CFrame,
	Side: CFrame,
	Alive: boolean,
	Cheer: boolean,
	Connections: { RBXScriptConnection },
}

local rng = Random.new()
local opening: { [Player]: boolean } = {}
local lastOpen: { [Player]: number } = {}
local lastReset: { [Player]: number } = {}
local lastTheme: { [Player]: number } = {}
local mascots: { [Plot]: Mascot } = {}

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function row(map: any, id: any): any
	if type(id) ~= "string" then
		return nil
	end
	local value = rawget(map, id)
	return if type(value) == "table" then value else nil
end

local function guarded(name: string, fn: (...any) -> ...any, ...: any): (boolean, any, any)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		warn("[Rebirth] " .. name .. " failed:", a)
		return false, nil, nil
	end
	return true, a, b
end

local function celebrate(player: Player, info: any)
	if player.Parent == Players then
		guarded("Celebrate", function()
			Remotes.Celebrate:FireClient(player, info)
		end)
	end
end

local function treating(player: Player): boolean
	local ok, busy = guarded("Treatment.busy", Treatment.busy, player)
	return ok and busy == true
end

local function view(player: Player, free: boolean): any
	return { Free = free, CanSave = PlayerData.canSave(player), Treating = treating(player) }
end

------------------------------------------------------------------------------------------------------------------
-- The walk boost (🌳 Quick Feet)
------------------------------------------------------------------------------------------------------------------

local function walkBoostOf(data: any): number
	if type(data) ~= "table" then
		return 0
	end
	return Pure.walkBoost(RebirthLogic.effects(data, Config, PerksData, TreeData))
end

local function applyWalk(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local boost = player:GetAttribute(WALK_ATTRIBUTE)
	if humanoid then
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed + (if type(boost) == "number" then boost else 0)
	end
end

local function refreshWalk(player: Player, data: any)
	if player.Parent ~= Players then
		return
	end
	local boost = walkBoostOf(data)
	if player:GetAttribute(WALK_ATTRIBUTE) ~= boost then
		player:SetAttribute(WALK_ATTRIBUTE, boost)
	end
	local character = player.Character
	if character then
		applyWalk(player, character)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The plot: Branches, the sign's 🏢 badge and the mascot
------------------------------------------------------------------------------------------------------------------

local function branchLabel(plot: Plot): TextLabel?
	local sign = plot.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	if not gui then
		return nil
	end
	local found = gui:FindFirstChild(BADGE_NAME)
	if found then
		return if found:IsA("TextLabel") then found else nil
	end
	-- A sign without one (a kit sign, or before PlotBuilder makes it): a small white pill in the top right corner.
	local label = Instance.new("TextLabel")
	label.Name = BADGE_NAME
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.fromScale(0.97, 0.05)
	label.Size = UDim2.fromScale(0.24, 0.24)
	label.BackgroundColor3 = Palette.White
	label.BackgroundTransparency = 0.05
	label.Font = Palette.DisplayFont
	label.TextColor3 = Palette.Ink
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	label.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Palette.Outline
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return label
end

local function mascotHome(plot: Plot): CFrame
	local pivot = plot.Model:GetPivot()
	local spot = plot.Model:FindFirstChild(MASCOT_SPOT, true)
	local at: Vector3
	if spot and spot:IsA("BasePart") then
		at = (spot.CFrame * CFrame.new(0, -spot.Size.Y / 2, 0)).Position -- markers rest on the ground
	elseif spot and spot:IsA("Attachment") then
		at = spot.WorldPosition
	else
		at = pivot:PointToWorldSpace(Vector3.new(MASCOT_FALLBACK.X, MASCOT_FALLBACK.Y, MASCOT_FALLBACK.Z))
	end
	return CFrame.new(at) * pivot.Rotation -- faces the street, like the plot
end

local function removeMascot(plot: Plot)
	local m = mascots[plot]
	if not m then
		return
	end
	mascots[plot] = nil
	m.Alive = false
	for _, connection in m.Connections do
		connection:Disconnect()
	end
	table.clear(m.Connections)
	m.Model:Destroy()
end

-- Idle hops to the side and back, and a happy spin after each cure at the plot. One end-pose write per hop
-- (NurseBuilder.hop); the clients draw the arc.
local function mascotLoop(m: Mascot)
	local away = false
	while m.Alive do
		local idle = rng:NextNumber(IDLE_MIN, IDLE_MAX)
		local waited = 0
		while m.Alive and not m.Cheer and waited < idle do
			waited += task.wait(POLL_SECONDS)
		end
		if not m.Alive or not m.Model.Parent then
			break
		end
		local at = if away then m.Side else m.Home
		local ok, landed
		if m.Cheer then
			m.Cheer = false
			ok, landed =
				guarded("mascot spin", NurseBuilder.hop, m.Model, at, at, CHEER_HEIGHT, CHEER_SECONDS, math.pi * 2)
		else
			local to = if away then m.Home else m.Side
			ok, landed = guarded("mascot hop", NurseBuilder.hop, m.Model, at, to, IDLE_HEIGHT, IDLE_SECONDS)
			if ok and landed then
				away = not away
			end
		end
		if not (ok and landed) then
			break -- the model went (the plot was released): stop
		end
	end
end

local function ensureMascot(plot: Plot)
	local existing = mascots[plot]
	if existing and existing.Alive and existing.Model.Parent == plot.Model then
		return
	end
	removeMascot(plot)
	local ok, model = guarded("CreatureBuilder.buildLook (mascot)", CreatureBuilder.buildLook, MASCOT_LOOK, MASCOT_NAME)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	guarded("CreatureBuilder.setMood (mascot)", CreatureBuilder.setMood, model, "Happy")
	local home = mascotHome(plot)
	model:PivotTo(home)
	model:SetAttribute("Mascot", true)
	CollectionService:AddTag(model, CreatureBuilder.MOTION_TAG) -- its hops are drawn on the clients
	model.Parent = plot.Model
	guarded("NurseBuilder.popIn (mascot)", NurseBuilder.popIn, model)

	local m: Mascot = {
		Plot = plot,
		Model = model,
		Home = home,
		Side = home * CFrame.new(MASCOT_STEP, 0, 0),
		Alive = true,
		Cheer = false,
		Connections = {},
	}
	mascots[plot] = m

	-- A patient at this plot turning "Cured" (Server/Patients sets State on the model): spin. Each patient's own
	-- connection goes with its model.
	local folder = plot.Model:FindFirstChild("Patients")
	if folder then
		local function watch(child: Instance)
			if not child:IsA("Model") then
				return
			end
			child:GetAttributeChangedSignal("State"):Connect(function()
				if m.Alive and child:GetAttribute("State") == "Cured" then
					m.Cheer = true
				end
			end)
		end
		for _, child in folder:GetChildren() do
			watch(child)
		end
		table.insert(m.Connections, folder.ChildAdded:Connect(watch))
	end
	task.spawn(mascotLoop, m)
end

-- Branches, the badge and the mascot follow the owner's count.
local function showBranch(plot: Plot, count: number)
	plot.Model:SetAttribute(BRANCHES_ATTRIBUTE, count)
	local label = branchLabel(plot)
	if label then
		local text, visible = Pure.badge(count)
		label.Text = text
		label.Visible = visible
	end
	if RebirthLogic.has(count, "Mascot") then
		ensureMascot(plot)
	else
		removeMascot(plot)
	end
end

local function clearBranch(plot: Plot)
	removeMascot(plot)
	plot.Model:SetAttribute(BRANCHES_ATTRIBUTE, 0)
	local label = branchLabel(plot)
	if label then
		label.Text = ""
		label.Visible = false
	end
end

local function refreshPlot(player: Player)
	local plot = Plots.getPlot(player)
	local data = PlayerData.get(player)
	if plot and plot.Owner == player and data then
		guarded("show the branch", showBranch, plot, data.Rebirth.Count)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The one gentle toast (once ever)
------------------------------------------------------------------------------------------------------------------

local function maybeTell(player: Player, data: any)
	local rebirth = data.Rebirth
	if rebirth.Told == true or not TutorialLogic.isDone(data.Tutorial) then
		return
	end
	if not RebirthLogic.canRebirth(data, Config) then
		return
	end
	local told = false
	PlayerData.update(player, function(d)
		if d.Rebirth.Told ~= true then
			d.Rebirth.Told = true
			told = true
		end
	end)
	if told then
		Remotes.news(player, MSG.Told)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Opening a branch
------------------------------------------------------------------------------------------------------------------

function Rebirth.count(player: Player): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return if data then data.Rebirth.Count else 0
end

function Rebirth.effects(player: Player): RebirthLogic.Effects
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return RebirthLogic.effects(data, Config, PerksData, TreeData)
end

-- Steps 2-7 of Rebirth.open (the caller holds the in-flight lock). `before` is the count the checks read.
local function openNow(player: Player, free: boolean, before: number): (boolean, string)
	-- 2. A treated patient cures on the spot first.
	guarded("Patients.reopen", Patients.reopen, player)

	-- 3. Re-check. From here nothing yields until the save has changed.
	local data = PlayerData.get(player)
	if not data or not PlayerData.isOpen(player) then
		return false, MSG.Oops
	end
	if data.Rebirth.Count ~= before then
		return false, MSG.Busy
	end
	local ok, why = Pure.check(data, Config, view(player, free))
	if not ok then
		return false, why
	end
	local rolls = { rng:NextNumber(), rng:NextNumber(), rng:NextNumber() }
	local offer = RebirthLogic.offer(data.Rebirth.Perks, PerksData, rolls, Config.Rebirth.OfferSize)

	-- 4. ONE update: the count it read must still be the count it writes; apply runs on a trial copy.
	local result: RebirthLogic.ApplyResult? = nil
	local failure: any = nil
	PlayerData.update(player, function(d)
		if d.Rebirth.Count ~= before then
			return
		end
		if not free and not RebirthLogic.canRebirth(d, Config) then
			return
		end
		local done, applied = Pure.atomic(d, Pure.APPLY_KEYS, function(trial)
			local out = RebirthLogic.apply(trial, Config, offer, CONTENT)
			trial.Rebirth.Told = true -- they know about branches now: the gentle toast never comes
			return true, out
		end)
		if done then
			result = applied
		else
			failure = applied
		end
	end)
	if failure ~= nil then
		warn("[Rebirth] apply failed; the save is unchanged:", failure)
	end
	local applied = result
	if not applied then
		return false, MSG.Oops
	end

	-- 5. The plot follows the save (the building follows Data.Level by itself: Server/Levels).
	guarded("Plots.syncRooms", Plots.syncRooms, player)
	refreshPlot(player)

	-- 6. Saved at once.
	local saveRan, wrote = guarded("PlayerData.saveNow", PlayerData.saveNow, player)
	if not (saveRan and wrote == true) and PlayerData.canSave(player) then
		warn("[Rebirth] saveNow didn't land; the autosave or the leave-save writes it")
	end

	-- 7. The celebrations, the gift nurse, the signal.
	for _, info in Pure.celebrations(applied) do
		celebrate(player, info)
	end
	for _, nurseId in applied.Pending do
		local ran, granted = guarded("Nurses.grant (gift)", Nurses.grant, player, nurseId, 0, "Gift")
		if not (ran and granted == true) and player.Parent == Players then
			Remotes.toast(player, MSG.GiftWaits)
		end
	end
	Rebirth.Reborn:Fire(player, applied.Count)
	return true, MSG.Opened
end

function Rebirth.open(player: Player, free: boolean?): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	local isFree = free == true
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	-- 1. The checks (§B3).
	local ok, why = Pure.check(data, Config, view(player, isFree))
	if not ok then
		return false, why
	end
	if opening[player] then
		return false, MSG.Busy
	end
	local now = os.clock()
	local last = lastOpen[player]
	if not isFree and last and now - last < OPEN_COOLDOWN then
		return false, Remotes.TOO_FAST
	end
	-- Claim before the first yield (roblox-networking): a second click can't pass the same checks.
	opening[player] = true
	lastOpen[player] = now
	local ran, opened, message = pcall(openNow, player, isFree, data.Rebirth.Count)
	opening[player] = nil
	if not ran then
		warn("[Rebirth] open failed:", opened)
		return false, MSG.Oops
	end
	return opened, message
end

------------------------------------------------------------------------------------------------------------------
-- Perk cards, the tree, themes and the gift nurse
------------------------------------------------------------------------------------------------------------------

-- Arguments are untrusted: this is the ChoosePerk remote's handler.
function Rebirth.choose(player: Player, perkId: any): (boolean, string)
	if not isPlayer(player) or not validId(perkId) then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	-- liveOffer: an offer whose cards were all renamed or removed since becomes the Fallback card, never a dead end.
	local offer = RebirthLogic.liveOffer(data.Rebirth.Offer, PerksData)
	if not table.find(offer, perkId) or table.find(data.Rebirth.Perks, perkId) then
		return false, MSG.NotOffered
	end
	local chosen = false
	PlayerData.update(player, function(d)
		chosen = Pure.atomic(d, Pure.CHOOSE_KEYS, function(trial)
			return RebirthLogic.choose(trial, perkId, PerksData, Config)
		end)
	end)
	if not chosen then
		return false, MSG.NotOffered
	end
	local perk = row(PerksData, perkId)
	if perk and perk.Kind == "StartRoom" then
		guarded("Plots.syncRooms", Plots.syncRooms, player) -- 🛁 Bath Ready: the room appears now
	end
	celebrate(player, Pure.perkCelebration(perkId, PerksData))
	return true, Pure.perkReply(perkId, PerksData)
end

-- Arguments are untrusted: this is the BuyNode remote's handler.
function Rebirth.buyNode(player: Player, nodeId: any): (boolean, string)
	if not isPlayer(player) or not validId(nodeId) then
		return false, MSG.Oops
	end
	local def = row(TreeData.Nodes, nodeId)
	if not def then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	local can, why = TreeLogic.canBuy(data.Rebirth.Tree, data.Rebirth.Points, nodeId, TreeData.Nodes)
	if not can then
		return false, why
	end
	local bought: boolean, rank: any = false, 0 -- rank: the new rank, or why not (a string)
	PlayerData.update(player, function(d)
		bought, rank = Pure.atomic(d, Pure.REBIRTH_KEYS, function(trial)
			local r = trial.Rebirth
			local again, message = TreeLogic.canBuy(r.Tree, r.Points, nodeId, TreeData.Nodes)
			if not again then
				return false, message
			end
			local tree, points = TreeLogic.buy(r.Tree, r.Points, nodeId, TreeData.Nodes)
			r.Tree = tree
			r.Points = points
			return true, tree[nodeId]
		end)
	end)
	if not bought then
		return false, if type(rank) == "string" then rank else MSG.Oops
	end
	refreshWalk(player, PlayerData.get(player))
	return true, Pure.nodeReply(def, rank)
end

-- This is the ResetTree remote's handler (it takes no arguments).
function Rebirth.resetTree(player: Player): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	if next(data.Rebirth.Tree) == nil then
		return false, MSG.NothingToReset
	end
	local now = os.clock()
	local last = lastReset[player]
	if last and now - last < RESET_COOLDOWN then
		return false, Remotes.TOO_FAST
	end
	local reset: boolean, back: any = false, 0
	PlayerData.update(player, function(d)
		reset, back = Pure.atomic(d, Pure.REBIRTH_KEYS, function(trial)
			local r = trial.Rebirth
			local refund = TreeLogic.refund(r.Tree, TreeData.Nodes)
			r.Points = math.min(RebirthLogic.MAX_POINTS, r.Points + refund)
			r.Tree = {}
			return true, refund
		end)
	end)
	if not reset then
		return false, MSG.Oops
	end
	lastReset[player] = now
	refreshWalk(player, PlayerData.get(player))
	return true, "🔄 Tree reset! 🌳" .. tostring(back) .. " back"
end

-- Arguments are untrusted: this is the SetTheme remote's handler.
function Rebirth.setTheme(player: Player, themeId: any): (boolean, string)
	if not isPlayer(player) or not validId(themeId) then
		return false, MSG.Oops
	end
	local theme = row(ThemesData, themeId)
	if not theme then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	local needs = math.max(0, math.floor(tonumber(theme.Rebirths) or 0))
	if data.Rebirth.Count < needs then
		return false, "Needs 🏢 R" .. tostring(needs)
	end
	local reply = theme.Icon .. " " .. theme.Name .. " look!"
	if RebirthLogic.theme(data, ThemesData) == themeId then
		return true, reply
	end
	local now = os.clock()
	local last = lastTheme[player]
	if last and now - last < THEME_COOLDOWN then
		return false, Remotes.TOO_FAST
	end
	local set = false
	PlayerData.update(player, function(d)
		if d.Rebirth.Count >= needs then
			d.Rebirth.Theme = themeId
			set = true
		end
	end)
	if not set then
		return false, MSG.Oops
	end
	lastTheme[player] = now
	return true, reply
end

-- This is the ClaimBranchNurse remote's handler (it takes no arguments).
function Rebirth.claimNurse(player: Player): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	local nurseId = Pure.firstPending(data.Rebirth.Pending, NursesData)
	if not nurseId then
		return false, MSG.NoGift
	end
	if data.Nurses[nurseId] ~= nil then
		-- Already on the roster (an admin gave it): the waiting gift just goes.
		PlayerData.update(player, function(d)
			local index = table.find(d.Rebirth.Pending, nurseId)
			if index then
				table.remove(d.Rebirth.Pending, index)
			end
		end)
		return true, MSG.AlreadyYours
	end
	-- Roster room, the charge (0) and the copy, and its Pending removal: ONE update inside Nurses.grant.
	local ran, ok, message = guarded("Nurses.grant (gift)", Nurses.grant, player, nurseId, 0, "Gift")
	if not ran then
		return false, MSG.Oops
	end
	return ok == true, if type(message) == "string" then message else ""
end

------------------------------------------------------------------------------------------------------------------
-- Admin hooks (Server/Admin checks the caller is an admin)
------------------------------------------------------------------------------------------------------------------

function Rebirth.adminRebirth(player: Player): (boolean, string)
	return Rebirth.open(player, true)
end

function Rebirth.adminPoints(player: Player): (boolean, string)
	if not isPlayer(player) or not PlayerData.get(player) then
		return false, MSG.Loading
	end
	local add = math.max(0, math.floor(Config.Rebirth.PointsPerRebirth))
	local saved = PlayerData.update(player, function(d)
		d.Rebirth.Points = math.min(RebirthLogic.MAX_POINTS, d.Rebirth.Points + add)
	end)
	if not saved then
		return false, MSG.Loading
	end
	return true, "🌳 +" .. tostring(add) .. " tree points!"
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

function Rebirth.start()
	Remotes.serve("OpenBranch", function(player: Player, confirm: any)
		if confirm ~= true then
			return false, MSG.Oops -- only the keep/reset screen's hold-to-confirm sends true
		end
		return Rebirth.open(player, false)
	end)
	Remotes.serve("ChoosePerk", function(player: Player, perkId: any)
		return Rebirth.choose(player, perkId)
	end)
	Remotes.serve("BuyNode", function(player: Player, nodeId: any)
		return Rebirth.buyNode(player, nodeId)
	end)
	Remotes.serve("ResetTree", function(player: Player)
		return Rebirth.resetTree(player)
	end)
	Remotes.serve("SetTheme", function(player: Player, themeId: any)
		return Rebirth.setTheme(player, themeId)
	end)
	Remotes.serve("ClaimBranchNurse", function(player: Player)
		return Rebirth.claimNurse(player)
	end)

	-- Plots: a free plot shows 0; an owned one follows its owner (also any assigned before this started).
	for _, plot in Plots.all() do
		if plot.Owner then
			local data = PlayerData.get(plot.Owner)
			guarded("show the branch", showBranch, plot, if data then data.Rebirth.Count else 0)
		else
			plot.Model:SetAttribute(BRANCHES_ATTRIBUTE, 0)
		end
	end
	Plots.PlotAssigned:Connect(function(owner: Player, plot: Plot)
		local data = PlayerData.get(owner)
		guarded("show the branch", showBranch, plot, if data then data.Rebirth.Count else 0)
	end)
	Plots.PlotReleased:Connect(function(_owner: Player, plot: Plot)
		guarded("clear the branch", clearBranch, plot) -- before Plots clears the plot
	end)

	PlayerData.Loaded:Connect(function(player: Player, data: any)
		refreshWalk(player, data)
	end)
	-- Every save change: the plot follows a new count, the walk a new tree, and the once-ever toast.
	PlayerData.Changed:Connect(function(player: Player, data: any)
		if not isPlayer(player) or player.Parent ~= Players or type(data) ~= "table" then
			return
		end
		local plot = Plots.getPlot(player)
		if plot and plot.Owner == player and plot.Model:GetAttribute(BRANCHES_ATTRIBUTE) ~= data.Rebirth.Count then
			guarded("show the branch", showBranch, plot, data.Rebirth.Count)
		end
		if player:GetAttribute(WALK_ATTRIBUTE) ~= walkBoostOf(data) then
			refreshWalk(player, data)
		end
		maybeTell(player, data)
	end)

	local function onJoin(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if humanoid and player.Character == character then
				applyWalk(player, character)
			end
		end)
		local data = PlayerData.get(player)
		if data then
			refreshWalk(player, data)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		opening[player] = nil
		lastOpen[player] = nil
		lastReset[player] = nil
		lastTheme[player] = nil
	end)
end

return Rebirth
