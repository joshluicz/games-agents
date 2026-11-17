--!strict
-- Stations: the supply shelf and the dispensary (Real Clinic build plan, Task 5; design §7, §8.2, §9). Server only.
--
-- Every `Station_<StationId>` in a plot's Building (Plaster, Ice, Bandage, Cast and Remedy, contract C2: found by
-- name, and again whenever a level-up or a rebirth rebuilds the Building) and in every placed room (Bath in the Bath
-- Room, Cocoa in the Winter Wing: Plots.observeRooms) gets a hold prompt `MakePrompt`, tagged `StationPrompt`
-- (CollectionService; clients use GetInstanceAddedSignal too, for streaming and rebuilds) with the attributes
-- `StationId` and `ItemId` (Data/Stations .Item; "" for the dispensary). Only people who may work the clinic
-- (Plots.canWork) can use them, and only while it has an owner: a free plot's prompts are switched off. A station
-- whose `Open` attribute is false (a supply the clinic's level hasn't opened: Bandage below Lv 2, Cast below Lv 3)
-- has its prompt switched off too, and a trigger on it is refused.
--
--   Supplies ("Take", ObjectText the station's icon): holding puts that station's item in your tray (Carry.add), with
--   a sparkle burst. Then Daily.onMake, Badges.onMade ("Made:<StationId>") and Tutorial.onMade.
--   The dispensary (Station_Remedy, "Dispense"; Data/Stations Dispense): the medicines are made only by a player here
--   (nurses never dispense). Holding opens a Dispense session (Server/Treatment) whose Options are the medicines bay
--   patients still need (Patients.neededMedicines and the rest of Patients.bayView's needs, the oldest first), less
--   the copies this player already carries and less a medicine their full tray holds nothing but, and only then cut
--   to Config.Dispensary.Options (3): a fourth needed medicine comes up once one of the first three is in hand. The session's Give puts the chosen medicine in your hands (the same full-tray swap as a supply), bursts
--   the sparkles and counts "Made:Remedy" (the old potion badge keeps climbing, shown "Pharmacist"), Daily.onMake and
--   Tutorial.onMade. Nothing to dispense: "💊 No prescriptions yet" (also the prompt's ObjectText, kept up to date
--   every second; otherwise it shows the needed medicines' icons), "🙌 Already in your hands!", or "🙌 Tray full!
--   Treat a patient." when the tray is full of the only medicine left to make (said when the hold begins, never
--   after both games).
--   Expert Dispensing (the clinic owner's Pharmacy2 rebirth unlock, Pure.pharmacyTier 2): the session's Dose band
--   is wider (Treatment, spec.Expert).
--   Tips: a dispense pays its tip at once (Treatment), but only while fewer dispenses of that medicine have tipped
--   than bay patients' needs of it were seen (a per-plot ledger over Patients.bayView: Pure.sync, Pure.claimTip). So
--   each need tips once, whichever patient the bottle goes to; two players dispensing the last needed medicine both
--   get it (a spare is just a held item to discard) and only one gets a tip, and throwing a medicine away and
--   dispensing it again never tips twice.
--
-- Hold time, checked on the server (the old Kitchen pattern). A prompt's hold runs on the client, so the server
-- times it itself: PromptButtonHoldBegan starts a hold (one at a time per player), and Triggered only counts when at
-- least the hold time has passed, less a small lag allowance. A trigger with no hold, a hold on another prompt, a
-- hold that's too short or stale, or a player who's too far away is ignored. The hold time is
-- Server/Boosts.makeSeconds(player, station) (Faster Hands, then MakeSpeed boosts) x the plot's team
-- (Nurses.team(plot).Make[station]) x its ability rush (Abilities.makeFactor: Busy Paws 0.5, Time Bubble 0), never
-- under Config.BoostMinMakeSeconds (Pure.holdSeconds). The shorter of the time when the hold began and when it ends
-- counts, so a rush that runs out mid-hold never makes a kid hold again.
--
-- Hold time on screen. A server-set HoldDuration replicates to everyone, but each player's speed differs. So the
-- server sets the SLOWEST time (Speed 0), which is never too short for anyone, and never changes it. Each client
-- shortens its own copy (the Snapshot's MakeSeconds per station, UI/Guide).
--
-- A full tray never blocks the clinic. Supplies are free, so taking something with a full tray swaps out the oldest
-- item that's different ("🔄 🩹 → 🧊"), first one nobody at this clinic needs (the bay patients' needs from
-- Patients.bayView, else the plot's QueueNeeds attribute). Only a tray already full of this very item refuses ("Tray
-- full!"), since a swap would change nothing.
--
-- Feedback is immediate: a refusal toasts when the hold BEGINS, so nobody holds for nothing. Toasts are short (≤ 6
-- words, icon first) and the same toast is sent at most once every 1.5 s per player.
--
-- Discard(itemId): the ✖ on a HUD hand throws that item away, so an unneeded item never leaves a player stuck.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Palette = require(Shared.Palette)
local ItemData = require(Shared.Data.Items)
local StationData = require(Shared.Data.Stations)
local Prices = require(Shared.Logic.Prices)
local Recipe = require(Shared.Logic.Recipe)
local RebirthLogic = require(Shared.Logic.Rebirth)
local Carry = require(script.Parent.Carry)
local Daily = require(script.Parent.Daily)
local Plots = require(script.Parent.Plots)
local PlayerData = require(script.Parent.PlayerData)
local Tutorial = require(script.Parent.Tutorial)
local Boosts = require(script.Parent.Boosts) -- MakeSpeed boosts
local Badges = require(script.Parent.Badges) -- station badges ("Made:<StationId>")
local Nurses = require(script.Parent.Nurses) -- team bonuses (Make)
local Abilities = require(script.Parent.Abilities) -- Busy Paws / Time Bubble
local Treatment = require(script.Parent.Treatment) -- the Dispense session

type Plot = Types.Plot

local Stations = {}

Stations.PROMPT_NAME = "MakePrompt"
Stations.PROMPT_TAG = "StationPrompt"

local TAKE_TEXT = "Take"
local DISPENSE_TEXT = "Dispense"
local BUILDING_NAME = "Building"
local ACTIVATION_DISTANCE = 10
local DISTANCE_SLACK = 8 -- studs of movement and lag allowed beyond the activation distance
local LAG_ALLOWANCE = 0.25 -- seconds: hold begin/trigger can arrive this much closer together than the hold time
local STALE_AFTER = 8 -- seconds past the hold time: a hold this old is not a real hold
local TOAST_COOLDOWN = 1.5
local REFRESH_SECONDS = 1 -- the dispensary's ObjectText follows the bay patients this often

local TRAY_FULL = "🙌 Tray full! Treat a patient."
local NOT_YOURS = "🔒 Not your clinic!"
local HOLD_LONGER = "✋ Hold a little longer!"
local NOT_OPEN = "🔒 Not open yet!"
local FINISH_GAME = "🎮 Finish your game first!"
local SWAP_ICON = "🔄"
local SWAP_ARROW = "→"

-- Told: the refusal already toasted when this hold began (not repeated when it completes). Needed: the hold time
-- when it began (a rush that ends mid-hold doesn't make it longer).
type Hold = { Prompt: ProximityPrompt, Started: number, Ended: number?, Told: string?, Needed: number }

-- One wired station: the instance named Station_<id> (it carries `Open`), the part holding its prompt.
type Wired = {
	Plot: Plot,
	StationId: string,
	Holder: Instance,
	Part: BasePart,
	Prompt: ProximityPrompt,
	Sparkles: ParticleEmitter,
}

local holds: { [Player]: Hold } = {}
local lastToast: { [Player]: { [string]: number } } = {}
local prompts: { [ProximityPrompt]: Wired } = {}
local wired: { [BasePart]: boolean } = {}
local claimed: { [Plot]: any } = {} -- the dispense-tip ledgers (Pure.ledger)
local warned: { [string]: number } = {}

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function report(label: string, err: any)
	local count = (warned[label] or 0) + 1
	warned[label] = count
	if count <= 3 then
		warn("[Stations] " .. label .. " failed: " .. tostring(err))
	end
end

local function toast(player: Player, text: string)
	local now = os.clock()
	local sent = lastToast[player]
	if not sent then
		sent = {}
		lastToast[player] = sent
	end
	if sent[text] and now - sent[text] < TOAST_COOLDOWN then
		return
	end
	sent[text] = now
	Remotes.toast(player, text)
end

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services and no upvalues: a scratch Lune harness loads this block on its own; the Data
-- tables come in as arguments)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.MSG = table.freeze({
	None = "💊 No prescriptions yet",
	Have = "🙌 Already in your hands!",
	Full = "🙌 Tray full! Treat a patient.",
})

-- Which carried item to give up to make room for `itemId` (`carried` oldest first): the oldest one that's
-- different and isn't covering something the clinic still needs (`needs`, duplicates counted), else the oldest one
-- that's different. nil when every carried item is `itemId` (swapping would change nothing).
function Pure.swapOut(carried: { string }, itemId: string, needs: { string }): string?
	local wanted: { [string]: number } = {}
	for _, need in needs do
		wanted[need] = (wanted[need] or 0) + 1
	end
	local oldest: string? = nil
	for _, item in carried do
		if item ~= itemId then
			oldest = oldest or item
			local left = wanted[item]
			if left and left > 0 then
				wanted[item] = left - 1 -- this one is spoken for
			else
				return item -- nobody needs it
			end
		end
	end
	return oldest
end

-- A number from another system that scales a hold: finite and >= 0, junk -> 1 (no change).
local function factor(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 1
	end
	return value
end

-- The hold time at a station. `base` = Boosts.makeSeconds (Faster Hands and MakeSpeed boosts), x `team`
-- (Nurses.team(plot).Make[station]: 1 = no team) x `rush` (Abilities.makeFactor: 1, 0.5, or 0 = the shortest hold),
-- never under `floor` (Config.BoostMinMakeSeconds) and never longer than `base`.
function Pure.holdSeconds(base: number, team: any, rush: any, floor: number): number
	local b = if type(base) == "number" and base == base and base > 0 then base else floor
	local low = math.min(b, math.max(0, floor))
	return math.clamp(b * math.min(factor(team), 1) * math.min(factor(rush), 1), low, b)
end

-- The dispensary's tier at a clinic whose owner has opened `rebirths` branches: 2 with the Pharmacy2 unlock
-- (Expert Dispensing: a wider Dose band; `has` = Logic/Rebirth.has), else 1.
function Pure.pharmacyTier(rebirths: any, has: (number, string) -> boolean): number
	local count = if type(rebirths) == "number" and rebirths == rebirths then rebirths else 0
	return if has(count, "Pharmacy2") then 2 else 1
end

local function isMedicine(items: any, itemId: any): boolean
	local row = if type(items) == "table" and type(itemId) == "string" then rawget(items, itemId) else nil
	return type(row) == "table" and row.Kind == "Medicine"
end

local function since(row: any): number
	local value = row.Since
	return if type(value) == "number" and value == value then value else math.huge
end

-- What the dispensing card offers this player. Every medicine a bay patient still needs: `needed`
-- (Patients.neededMedicines: distinct, the oldest first, but cut to the card's size) and then the rest of the needs
-- in `rows` (Patients.bayView, the longest wait first), kept to known medicines. Less what they already carry: `rows`
-- counts each medicine's open needs, and one whose every need is already in the player's hands is left out (a medicine
-- the rows don't mention is kept: `needed` says so). Less what can't land in their hands: with a `full` tray that
-- holds nothing but that very medicine, a swap would change nothing. Only THEN cut to `max` (Config.Dispensary.Options,
-- default 3), so a fourth needed medicine comes up as soon as one of the first three is in hand.
-- Returns the options and, when there are none, why: "None" (nothing is needed), "Have" (everything needed is in
-- your hands) or "Full" (the tray is full of it: hand one over first).
function Pure.dispenseOptions(
	needed: any,
	rows: any,
	carried: any,
	items: any,
	max: any,
	full: any
): ({ string }, string)
	local list: { string } = {}
	local function add(itemId: any)
		if isMedicine(items, itemId) and not table.find(list, itemId) then
			table.insert(list, itemId)
		end
	end
	if type(needed) == "table" then
		for _, itemId in needed do
			add(itemId)
		end
	end
	local count: { [string]: number }? = nil
	if type(rows) == "table" then
		local counted: { [string]: number } = {}
		local sorted: { any } = {}
		for _, row in rows do
			if type(row) == "table" and type(row.Needs) == "table" then
				table.insert(sorted, row)
			end
		end
		table.sort(sorted, function(x, y)
			return since(x) < since(y)
		end)
		for _, row in sorted do
			for _, itemId in row.Needs do
				if type(itemId) == "string" then
					counted[itemId] = (counted[itemId] or 0) + 1
					add(itemId)
				end
			end
		end
		count = counted
	end
	if #list == 0 then
		return {}, "None"
	end
	local hands: { string } = {}
	if type(carried) == "table" then
		for _, itemId in carried do
			if type(itemId) == "string" then
				table.insert(hands, itemId)
				if count and count[itemId] then
					count[itemId] -= 1
				end
			end
		end
	end
	local limit = if type(max) == "number" and max == max and max >= 1 then math.floor(max) else 3
	local out: { string } = {}
	local blocked = 0
	for _, itemId in list do
		local left = if count then count[itemId] else nil
		if left == nil or left > 0 then
			local only = #hands > 0
			for _, held in hands do
				if held ~= itemId then
					only = false
					break
				end
			end
			if full == true and only then
				blocked += 1 -- a full tray of this very medicine: nothing to swap out
			elseif #out < limit then
				table.insert(out, itemId)
			end
		end
	end
	if #out > 0 then
		return out, ""
	end
	return out, if blocked > 0 then "Full" else "Have"
end

local function patientKey(row: any): string?
	local id = if type(row) == "table" then row.PatientId else nil
	if type(id) == "number" and id == id then
		return tostring(id)
	end
	return if type(id) == "string" and id ~= "" then id else nil
end

-- The dispense-tip ledger: one tip per NEED, whichever patient the bottle goes to. Seen = every bay patient's
-- medicine need the ledger has seen ("<patient>:<item>", kept while that patient is in a bay, given or not); Tips =
-- per medicine, the dispenses that tipped. A dispense of `itemId` tips while fewer have tipped than needs were seen.
-- So with two patients needing cough syrup two dispenses tip, in either order of handing over; two players
-- dispensing the last needed medicine get one tip between them; and throwing a medicine away and dispensing it again
-- never tips twice.
type Ledger = { Seen: { [string]: boolean }, Tips: { [string]: number } }

function Pure.ledger(): Ledger
	return { Seen = {}, Tips = {} }
end

-- Brings the ledger up to date with the bays (`rows`, Patients.bayView): new needs are seen; a patient who left its
-- bay takes its needs along, and each takes one tip of its medicine with it (the need and its tip are both history).
-- Junk rows: no change.
function Pure.sync(ledger: Ledger, rows: any)
	if type(rows) ~= "table" then
		return
	end
	local live: { [string]: boolean } = {}
	for _, row in rows do
		local patient = patientKey(row)
		if patient then
			live[patient] = true
			if type(row.Needs) == "table" then
				for _, itemId in row.Needs do
					if type(itemId) == "string" then
						ledger.Seen[patient .. ":" .. itemId] = true
					end
				end
			end
		end
	end
	for key in ledger.Seen do
		local patient, itemId = string.match(key, "^(.*):([^:]*)$")
		if not (patient and live[patient]) then
			ledger.Seen[key] = nil
			if itemId and ledger.Tips[itemId] then
				local left = ledger.Tips[itemId] - 1
				ledger.Tips[itemId] = if left > 0 then left else nil
			end
		end
	end
end

-- Whether a dispense of `itemId` may tip now (and counts it when it may). Pure.sync first.
function Pure.claimTip(ledger: Ledger, itemId: any): boolean
	if type(itemId) ~= "string" then
		return false
	end
	local needs = 0
	local suffix = ":" .. itemId
	for key in ledger.Seen do
		if string.sub(key, -#suffix) == suffix then
			needs += 1
		end
	end
	local tipped = ledger.Tips[itemId] or 0
	if tipped >= needs then
		return false
	end
	ledger.Tips[itemId] = tipped + 1
	return true
end

-- The dispensary prompt's ObjectText: the needed medicines' icons, or "💊 No prescriptions yet".
function Pure.objectText(needed: any, items: any): string
	local icons: { string } = {}
	if type(needed) == "table" then
		for _, itemId in needed do
			if isMedicine(items, itemId) then
				local icon = rawget(items, itemId).Icon
				table.insert(icons, if type(icon) == "string" then icon else "❔")
			end
		end
	end
	if #icons == 0 then
		return Pure.MSG.None
	end
	return "💊 " .. table.concat(icons, " ")
end
-- PURE-END

------------------------------------------------------------------------------------------------------------------
-- Patients (C6), asked lazily so this module never joins a require cycle with it
------------------------------------------------------------------------------------------------------------------

local patientsModule: any = nil

local function patients(): any
	if patientsModule == nil then
		local ok, loaded = pcall(require, script.Parent.Patients)
		if not ok then
			report("require Patients", loaded)
		end
		patientsModule = if ok and type(loaded) == "table" then loaded else false
	end
	return if patientsModule then patientsModule else nil
end

-- Patients.<name>(plotModel), guarded: nil when it isn't there or errors.
local function ask(name: string, plot: Plot): any
	local api = patients()
	local fn = if api then api[name] else nil
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, plot.Model)
	if not ok then
		report("Patients." .. name, result)
		return nil
	end
	return result
end

------------------------------------------------------------------------------------------------------------------
-- Reads
------------------------------------------------------------------------------------------------------------------

-- What everyone at this clinic still needs: the bay patients' needs (Patients.bayView), else the plot's QueueNeeds.
local function clinicNeeds(plot: Plot?): { string }
	if not plot then
		return {}
	end
	local rows = ask("bayView", plot)
	if type(rows) == "table" then
		local out: { string } = {}
		for _, row in rows do
			if type(row) == "table" and type(row.Needs) == "table" then
				for _, itemId in row.Needs do
					if type(itemId) == "string" then
						table.insert(out, itemId)
					end
				end
			end
		end
		return out
	end
	return Recipe.split(plot.Model:GetAttribute("QueueNeeds"))
end

-- The item a full tray gives up to make room for `itemId` (Pure.swapOut). nil when the tray has room, or holds
-- nothing but `itemId`.
local function swapOut(player: Player, itemId: string, plot: Plot?): string?
	if not Carry.isFull(player) then
		return nil
	end
	return Pure.swapOut(Carry.items(player), itemId, clinicNeeds(plot))
end

-- The dispensary's tier at this clinic: its owner's branches (the Pharmacy2 unlock = Expert Dispensing).
local function pharmacyTier(plot: Plot): number
	local owner = plot.Owner
	local data = if owner then PlayerData.get(owner) else nil
	local rebirths = if data and type(data.Rebirth) == "table" then data.Rebirth.Count else 0
	return Pure.pharmacyTier(rebirths, RebirthLogic.has)
end

-- The Dispense card's options for this player, and why there are none ("None" | "Have").
local function dispenseOptions(player: Player, plot: Plot): ({ string }, string)
	return Pure.dispenseOptions(
		ask("neededMedicines", plot),
		ask("bayView", plot),
		Carry.items(player),
		ItemData,
		Config.Dispensary and Config.Dispensary.Options,
		Carry.isFull(player)
	)
end

local function iconOf(itemId: string): string
	local item = rawget(ItemData :: any, itemId)
	return if item then item.Icon else "❔"
end

local function isOpen(w: Wired): boolean
	return w.Holder:GetAttribute("Open") ~= false
end

-- Why this player can't use this station right now, or nil if they can.
local function refusal(player: Player, w: Wired): string?
	local plot = w.Plot
	if not plot.Owner or not Plots.canWork(player, plot) then
		return NOT_YOURS
	end
	if not isOpen(w) then
		return NOT_OPEN
	end
	local station = StationData[w.StationId]
	if station.Dispense == true then
		if Treatment.busy(player) then
			return FINISH_GAME
		end
		local options, why = dispenseOptions(player, plot)
		if #options == 0 then
			return if why == "Have" then Pure.MSG.Have elseif why == "Full" then Pure.MSG.Full else Pure.MSG.None
		end
		return nil
	end
	if Carry.isFull(player) and swapOut(player, station.Item, plot) == nil then
		return TRAY_FULL -- full of this very item already
	end
	return nil
end

-- The player is alive and standing near the station (the prompt's own range, plus some slack).
local function isNear(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false
	end
	return (root.Position - part.Position).Magnitude <= ACTIVATION_DISTANCE + DISTANCE_SLACK
end

-- Faster Hands, then the player's MakeSpeed boosts at this station (Server/Boosts), then the plot's team and ability
-- rush (Pure.holdSeconds). Other systems are asked in a pcall: a bug there only means no bonus here.
local function makeSeconds(player: Player, stationId: string, plot: Plot): number
	local ok, seconds = pcall(Boosts.makeSeconds, player, stationId)
	local base = if ok and type(seconds) == "number" and seconds > 0 then seconds else Prices.makeSeconds(0, Config)
	local teamOk, team = pcall(Nurses.team, plot)
	local make = if teamOk and type(team) == "table" and type(team.Make) == "table" then team.Make[stationId] else nil
	local rushOk, rush = pcall(Abilities.makeFactor, plot)
	return Pure.holdSeconds(base, make, if rushOk then rush else 1, Config.BoostMinMakeSeconds)
end

-- A Station_<id> is a Part by contract; a kit might use a Model, so fall back to its main part.
local function stationPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Candy pop (memory-20261116-007): sparkles in the station's own full colour that turn candy yellow as they fall.
local function sparkleEmitter(part: BasePart, color: Color3): ParticleEmitter
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MakeSparkles"
	sparkles.Enabled = false
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, Palette.Candy.Yellow),
	})
	sparkles.LightEmission = 0.35 -- mostly normal blending, so the colour stays saturated in daylight
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.42),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0, 0.3)
	sparkles.Lifetime = NumberRange.new(0.5, 0.9)
	sparkles.Speed = NumberRange.new(4, 8)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Acceleration = Vector3.new(0, -6, 0)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Parent = part
	return sparkles
end

-- Emit() on the server never reaches players, so switch the emitter on for a moment instead (the Enabled change
-- replicates and each client makes the burst itself).
local function burst(sparkles: ParticleEmitter)
	sparkles.Rate = 90
	sparkles.Enabled = true
	task.delay(0.16, function()
		sparkles.Enabled = false
	end)
end

-- After anything lands in a player's hands here: daily goals, the station's badge, the tutorial.
local function made(player: Player, itemId: string, stationId: string, plot: Plot)
	local ok, err = pcall(Daily.onMake, player, itemId)
	if not ok then
		report("Daily.onMake", err)
	end
	local badgeOk, badgeErr = pcall(Badges.onMade, player, stationId)
	if not badgeOk then
		report("Badges.onMade", badgeErr)
	end
	local tutorialOk, tutorialErr = pcall(Tutorial.onMade, player, itemId, plot)
	if not tutorialOk then
		report("Tutorial.onMade", tutorialErr)
	end
end

-- Puts `itemId` in the player's hands; a full tray swaps its oldest different item for it (supplies are free, so
-- nothing is lost). false (and a toast) when it can't.
local function putInHands(player: Player, itemId: string, plot: Plot): boolean
	local swapped = swapOut(player, itemId, plot)
	if swapped then
		Carry.take(player, swapped)
	end
	if not Carry.add(player, itemId) then
		if swapped then
			Carry.add(player, swapped) -- couldn't make it after all: put the old one back
		end
		toast(player, TRAY_FULL)
		return false
	end
	if swapped then
		toast(player, SWAP_ICON .. " " .. iconOf(swapped) .. " " .. SWAP_ARROW .. " " .. iconOf(itemId))
	end
	return true
end

-- The plot's tip ledger, brought up to date with its bays. nil when the bays can't be read.
local function ledgerOf(plot: Plot): any
	local rows = ask("bayView", plot)
	if type(rows) ~= "table" then
		return nil
	end
	local ledger = claimed[plot]
	if not ledger then
		ledger = Pure.ledger()
		claimed[plot] = ledger
	end
	Pure.sync(ledger, rows)
	return ledger
end

-- Whether a dispense of `itemId` at this clinic may tip: a need is left that nobody's dispense has tipped for yet.
local function claimTip(plot: Plot, itemId: string): boolean
	local ledger = ledgerOf(plot)
	return ledger ~= nil and Pure.claimTip(ledger, itemId)
end

------------------------------------------------------------------------------------------------------------------
-- Using a station
------------------------------------------------------------------------------------------------------------------

-- A supply: into the hands, with the sparkles.
local function take(player: Player, w: Wired)
	local itemId = StationData[w.StationId].Item
	if not putInHands(player, itemId, w.Plot) then
		return
	end
	burst(w.Sparkles)
	made(player, itemId, w.StationId, w.Plot)
end

-- The dispensary: opens a Dispense session. Its Give lands the chosen medicine when the session settles.
local function dispense(player: Player, w: Wired)
	local plot = w.Plot
	local options = dispenseOptions(player, plot)
	if #options == 0 then
		return -- the refusal above already said why
	end
	local function give(itemId: string): (boolean, boolean)
		if player.Parent ~= Players or not putInHands(player, itemId, plot) then
			return false, false
		end
		burst(w.Sparkles)
		made(player, itemId, w.StationId, plot) -- "Made:Remedy" counts every dispense
		return true, claimTip(plot, itemId)
	end
	local spec: Treatment.Spec = {
		Plot = plot,
		PatientId = "",
		Kind = "Dispense",
		Items = {},
		Position = w.Part.Position + Vector3.new(0, 3, 0),
		Counter = w.Part.Position,
		TipSoFar = 0,
		Options = options,
		Expert = pharmacyTier(plot) >= 2,
		Give = give,
	}
	local ok, opened = pcall(Treatment.open, player, spec)
	if not ok then
		report("Treatment.open (Dispense)", opened)
	end
	if not (ok and type(opened) == "number") then
		toast(player, Remotes.OOPS)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Wiring one station
------------------------------------------------------------------------------------------------------------------

local function refresh(w: Wired, open: boolean?)
	local on = if open == nil then w.Plot.Owner ~= nil else open
	w.Prompt.Enabled = on and isOpen(w)
end

local function wireStation(plot: Plot, holder: Instance, part: BasePart, stationId: string)
	local station = StationData[stationId]
	if not station or wired[part] then
		return
	end
	wired[part] = true
	local dispensary = station.Dispense == true

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Stations.PROMPT_NAME
	prompt.ActionText = if dispensary then DISPENSE_TEXT else TAKE_TEXT
	prompt.ObjectText = if dispensary then Pure.MSG.None else station.Icon
	prompt.HoldDuration = Prices.makeSeconds(0, Config) -- the slowest; clients shorten their own copy
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StationId", stationId)
	prompt:SetAttribute("ItemId", station.Item)
	CollectionService:AddTag(prompt, Stations.PROMPT_TAG)

	local w: Wired = {
		Plot = plot,
		StationId = stationId,
		Holder = holder,
		Part = part,
		Prompt = prompt,
		Sparkles = sparkleEmitter(part, station.Color),
	}
	refresh(w)

	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local why = refusal(player, w)
		holds[player] = {
			Prompt = prompt,
			Started = os.clock(),
			Ended = nil,
			Told = why,
			Needed = makeSeconds(player, stationId, plot),
		}
		if why then
			toast(player, why) -- say it now, not after a hold that can't work
		end
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		local hold = holds[player]
		if hold and hold.Prompt == prompt and not hold.Ended then
			hold.Ended = os.clock()
		end
	end)

	prompt.Triggered:Connect(function(player: Player)
		local hold = holds[player]
		holds[player] = nil
		if not hold or hold.Prompt ~= prompt then
			return -- no hold on THIS prompt: a spoofed or overlapping trigger
		end
		local now = os.clock()
		-- The shorter of the time when the hold began and now: a rush ending mid-hold never costs a kid a redo.
		local needed = math.min(hold.Needed, makeSeconds(player, stationId, plot))
		if now - hold.Started > needed + STALE_AFTER then
			return
		end
		if (hold.Ended or now) - hold.Started + LAG_ALLOWANCE < needed then
			toast(player, HOLD_LONGER)
			return
		end
		if not isNear(player, part) then
			return
		end
		local why = refusal(player, w)
		if why then
			if why ~= hold.Told then
				toast(player, why)
			end
			return
		end
		if dispensary then
			dispense(player, w)
		else
			take(player, w)
		end
	end)

	local openChanged = holder:GetAttributeChangedSignal("Open"):Connect(function()
		refresh(w)
	end)
	prompt.Destroying:Once(function()
		openChanged:Disconnect()
		prompts[prompt] = nil
		wired[part] = nil
	end)
	prompts[prompt] = w
	prompt.Parent = part -- parent last: it replicates once, fully set up
end

-- One Station_<id> (a Building's Part, a room's Part, or a kit's Model).
local function wireOne(plot: Plot, instance: Instance)
	local stationId = string.match(instance.Name, "^Station_(%w+)$")
	if not stationId then
		return
	end
	if not rawget(StationData :: any, stationId) then
		warn("[Stations] Unknown station", instance:GetFullName())
		return
	end
	local part = stationPart(instance)
	if part then
		wireStation(plot, instance, part, stationId)
	else
		warn("[Stations] No part to hold the prompt in", instance:GetFullName())
	end
end

local function wireAll(plot: Plot, container: Instance)
	for _, descendant in container:GetDescendants() do
		wireOne(plot, descendant)
	end
end

-- The Building's stations now, and a rebuilt Building's (a level-up, a rebirth, a theme) as it arrives.
local function wireBuilding(plot: Plot, building: Instance)
	wireAll(plot, building)
	building.DescendantAdded:Connect(function(descendant)
		wireOne(plot, descendant)
	end)
end

local function watchPlot(plot: Plot)
	local building = plot.Model:FindFirstChild(BUILDING_NAME)
	if building then
		wireBuilding(plot, building)
	end
	plot.Model.ChildAdded:Connect(function(child)
		if child.Name == BUILDING_NAME then
			wireBuilding(plot, child)
		end
	end)
end

local function setPlotOpen(plot: Plot, open: boolean)
	for _, w in prompts do
		if w.Plot == plot then
			refresh(w, open)
		end
	end
end

-- The dispensary's ObjectText follows what the bay patients need ("💊 No prescriptions yet" when nothing).
local function refreshDispensaries()
	for prompt, w in prompts do
		if StationData[w.StationId].Dispense == true then
			local text = if w.Plot.Owner
				then Pure.objectText(ask("neededMedicines", w.Plot), ItemData)
				else Pure.MSG.None
			if prompt.ObjectText ~= text then
				prompt.ObjectText = text
			end
			if w.Plot.Owner and claimed[w.Plot] then
				ledgerOf(w.Plot) -- the tip ledger sees every need while it is open
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

-- Discard(itemId): the ✖ on a HUD hand throws that item away, so an unneeded item never leaves a player stuck.
-- Free, no confirm: supplies cost nothing and a medicine is dispensed again in a moment.
local function discard(player: Player, itemId: any): (boolean, string)
	if type(itemId) ~= "string" or rawget(ItemData :: any, itemId) == nil then
		return false, Remotes.OOPS
	end
	if not Carry.take(player, itemId) then
		return false, "🙌 Not in your hands!"
	end
	return true, "🗑️ " .. iconOf(itemId)
end

function Stations.start()
	Plots.observeRooms(function(plot: Plot, _roomId: string, roomModel: Model)
		wireAll(plot, roomModel)
	end)
	for _, plot in Plots.all() do
		watchPlot(plot)
	end
	Remotes.serve("Discard", discard)

	-- PlotReleased runs before the plot is cleared (plot.Owner is still set): switch its prompts off.
	Plots.PlotReleased:Connect(function(_player: Player, plot: Plot)
		setPlotOpen(plot, false)
		claimed[plot] = nil
	end)
	Plots.PlotAssigned:Connect(function(_player: Player, plot: Plot)
		setPlotOpen(plot, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
		lastToast[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			local ok, err = pcall(refreshDispensaries)
			if not ok then
				report("the dispensary text", err)
			end
		end
	end)
end

return Stations
