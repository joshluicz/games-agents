--!strict
-- Client entry point (build plan Task 0). Loads every UI and Feel module that exists, each in its own pcall, and
-- calls its init(ctx). A module that's missing or broken is reported and skipped: the rest still run.
--
-- ctx (Types.Ctx):
--   ctx.Player, ctx.Remotes, ctx.Config
--   ctx.Data          every Shared/Data table by name (Data.Rooms, Data.Patients, ...); maps have .Order
--   ctx.State         the latest Snapshot (a default one until the server's first arrives)
--   ctx.onState(fn)   calls fn(ctx.State) now, then on every new snapshot; returns a disconnect function
--   ctx.toast(text)   a local toast, shown the same way as server toasts
--   ctx.on(event, fn) / ctx.fire(event, ...)   a tiny client bus between modules; on() returns a disconnect
-- Bus events:
--   "Toast" (text)                             every toast, server or local; UI.Toasts shows them
--   "Open" (name, tab?)                        name = "Shop" | "Book" | "Mailbox" | "Goals" | "Gifts" | "Badges" |
--                                              "Boards" | "Admin"; Shop tab = "Upgrades" | "Rooms" | "Decor" (Hud
--                                              buttons, DayReportPanel's Go button; "Boards" from the HUD's 🏆 Top;
--                                              "Admin" from the ⚙️ panel's 🛠️, admins only)
--   "ModalOpened" (name, hudMode) · "ModalClosed" (name, hudMode)   a panel opened or closed (UI/Modal;
--                                          hudMode "Panel" | "Game" | "None": what the HUD hides meanwhile)
--   "SkipTutorial" () · "ReplayTutorial" ()   the ⚙️ rows (Hud): UI/Tutorial shows the confirm and asks the remote
--   "BookNew" (count)                          unseen new Book pages, for the 📖 dot (BookPanel -> Hud)
--   "Purchased" (kind, id)                     a Purchase the server said yes to (Shop)
--   "DecorPlaced" (slotKey, decorId?)          a PlaceDecor the server said yes to (Shop; nil = put away)
--   "Claimed" ("Mailbox" | "Goal" | "PlayGift", id?)   a claim the server said yes to (Mailbox, PlayGifts)
--   "Cheer" (icon, text, color?)               a reward banner: a badge tier, a Doctor rank (BadgeBook shows it)
--   "Sound" (name, volumeScale?)               plays a Feel/Sounds cue
--   "SetReduceEffects" (on) · "SetMusicMuted" (on)   the comfort switches (Feel/Atmosphere, Music.client)
-- Depth update (docs/plan/2026-11-16-depth-update-build-plan.md §B9). The server events TreatStart, NurseNews, Shout
-- and Celebrate are forwarded to the bus under the same names (payload types in Shared/Types):
--   "TreatStart" (session)                     play these mini-games (UI.MiniGames)
--   "MiniGameRated" (game, rating)             one mini-game ended, the client's own rating (UI.MiniGames -> Feel)
--   "TreatDone" (outcome, session)             the server's TreatResult reply: ratings, tip, combo (UI.MiniGames)
--   "NurseNews" (info) · "NursesNew" (count)   a nurse seen/hired/levelled... · unseen Journal news (UI.NursePanel ->
--                                              the Hud's 👩‍⚕️ dot)
--   "Shout" (info)                             belt news for everyone (UI.BeltView turns it into a Banner)
--   "Banner" (spec)                            a big top banner, optional countdown (UI.BeltView -> UI.Toasts)
--   "Celebrate" (info)                         rays + confetti + a big title (UI.Celebrate); also fired by Feel/CureFX
--                                              for a new room: Kind "Room" with an extra Room = <RoomId>
--   "CelebrateClosed" (kind)                   a celebration screen closed (UI.Celebrate; UI.Tutorial rings 📖 for a
--                                              few seconds after the "Tutorial" finale)
--   "Open" ("Nurses") · "Open" ("Shop", "Hospital")   the Nurses panel; the Shop's Hospital tab
--   "Open" ("NurseOdds")                       the belt's odds popup (UI/BeltView; UI/NursePanel's 🎲 chips open it too)
-- Progression v2 (docs/plan/2026-11-16-progression-v2-build-plan.md §B9). The server events AgencyNews, MarketNews and
-- BeltScout are forwarded to the bus under the same names too:
--   "AgencyNews" (view) · "MarketNews" (view) · "BeltScout" (info)   the Agency as you see it · the Market's
--                                              listings · the next belt arrival's rarity (🔭 Belt Scout owners)
--   "Open" ("Nurses", "Team" | "Branch" | rarity)   the 👩‍⚕️ panel ("Team" = your roster page, "Branch" = the 🏢
--                                              Journal page of rebirth-only nurses; Hud, anyone)
--   "Open" ("Branch", "Open" | "Perks" | "Tree" | "Themes")   UI.BranchPanel (from the Shop's 🏥 tab, and "Perks"
--                                              after the Rebirth celebration)
--   "Open" ("Agency", tab?) · "Open" ("Market", tab?)   UI.AgencyPanel (tab "Hire" | "Sell") · UI.MarketPanel (tab
--                                              "Buy" | "Sell" | "Mine") (NursePanel's buttons, the kiosks)
--   "Sell" (nurseId) · "List" (nurseId)        NursePanel's card buttons -> UI.AgencyPanel (the sell confirm) ·
--                                              UI.MarketPanel (the list flow)
--   "Open" ("Lift", floors)                    UI.LiftPanel itself (a LiftPrompt's client Triggered)
-- Client-only LocalPlayer attributes (set on this client, never by the server, never replicated): ReduceEffects
-- (the ✨/💤 calm-effects switch in the Hud's ⚙️ panel; Kit.reducedMotion() honours it) and MusicMuted (🎵/🔇).
-- The first snapshot: until the server's arrives, ctx.State is a default one with Tutorial = 0 ("not known yet"),
-- so the HUD starts calm (only 💰) and no tutorial card shows.
-- Module order: UI.Toasts first, then the rest of UI (UI.Tutorial last), then Feel. Theme, Kit, Modal (the modal
-- template, look overhaul) and Wayfinder (the tutorial's world guide) are libraries, not inited. ctx.Data.Guide is
-- the tutorial's guide nurse (it has no .Order). ctx.Data also has the depth update's Nurses, Rarities and Levels (Levels is an array), and Progression
-- v2's Jobs, Departments, Abilities, Perks, Tree and Themes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Roblox's own People list opens top-right on computers and covers the HUD's timer and visitor chips. The HUD
-- already shows cash and stars, so hide it (players still see who's here via Roblox's menu).
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local Schema = require(Shared:WaitForChild("Logic"):WaitForChild("Schema"))

local UI_MODULES = {
	"Toasts",
	"Hud",
	"Shop",
	"BookPanel",
	"DayReportPanel",
	"Mailbox",
	"PlayGifts",
	"BadgeBook",
	"Guide",
	"PromptFilter",
	"AdminPanel",
	"Boards",
	"Celebrate",
	"MiniGames",
	"NursePanel",
	"BeltView",
	"AgencyPanel",
	"MarketPanel",
	"BranchPanel",
	"LiftPanel",
	"Tutorial",
}
-- Feel.CreatureProps is CreatureActing's library. CreatureMotion moves each creature's Root (hops, scale) and
-- CreatureActing its Motor6Ds (the ailment acting), so both run on every patient.
-- Feel.Cutaway (look overhaul): hides the storeys above you while you stand inside your hospital.
local FEEL_MODULES = { "Sounds", "CureFX", "Atmosphere", "CreatureMotion", "CreatureActing", "HospitalFX", "Cutaway" }
-- Server events forwarded to the bus under the same name (build plan §B9; Progression v2 §B9)
local FORWARDED_EVENTS = { "TreatStart", "NurseNews", "Shout", "Celebrate", "AgencyNews", "MarketNews", "BeltScout" }
local DATA_NAMES = {
	"Ailments",
	"Stations",
	"Items",
	"Patients",
	"Regulars",
	"Rooms",
	"Upgrades",
	"Decor",
	"DailyGoals",
	"Wings",
	"Variants",
	"Playtime",
	"Boosts",
	"Badges",
	"Nurses",
	"Rarities",
	"Levels",
	-- Progression v2
	"Jobs",
	"Departments",
	"Abilities",
	"Perks",
	"Tree",
	"Themes",
	-- Look overhaul
	"Guide",
}

local dataFolder = Shared:WaitForChild("Data")
local Data = {}
for _, name in DATA_NAMES do
	Data[name] = require(dataFolder:WaitForChild(name) :: ModuleScript)
end

local function defaultSnapshot(): Types.Snapshot
	local data = Schema.default()
	return {
		Upgrades = data.Upgrades,
		Rooms = data.Rooms,
		Decor = data.Decor,
		Book = data.Book,
		Story = data.Story,
		Daily = data.Daily,
		Cash = 0,
		Stars = 0,
		Cured = 0,
		MailboxReady = false,
		PlotIndex = nil,
		TodaysVisitor = "",
		VisitorStatus = "None",
		IsWinter = false,
		Tutorial = 0, -- not known yet (Logic/Tutorial: 1..8 = in the tutorial, 9 = done)
		TutorialCures = 0,
		TutorialReplay = false,
		Playtime = data.Playtime,
		Boosts = { Timed = {}, Permanent = {}, Branch = {}, Rebirth = { Cash = 1, Stars = 1 } },
		MakeSeconds = {},
		Stats = data.Stats,
		Badges = data.Badges,
		Level = data.Level,
		Nurses = data.Nurses,
		NurseIndex = data.NurseIndex,
		JournalSets = data.JournalSets,
		Simple = data.Simple,
		Rebirth = data.Rebirth,
	}
end

------------------------------------------------------------------------------------------------------------------
-- The bus and the state
------------------------------------------------------------------------------------------------------------------

local bus: { [string]: Signal.Signal } = {}
local listeners: { [string]: number } = {}
local stateChanged = Signal.new()

local function event(name: string): Signal.Signal
	local signal = bus[name]
	if not signal then
		signal = Signal.new()
		bus[name] = signal
	end
	return signal
end

local ctx = {} :: Types.Ctx
ctx.Player = Players.LocalPlayer
ctx.Remotes = Remotes
ctx.Config = Config
ctx.Data = Data :: any
ctx.State = defaultSnapshot()

function ctx.on(name: string, fn: (...any) -> ()): () -> ()
	local connection = event(name):Connect(fn)
	listeners[name] = (listeners[name] or 0) + 1
	return function()
		if connection.Connected then
			connection:Disconnect()
			listeners[name] -= 1
		end
	end
end

function ctx.fire(name: string, ...: any)
	event(name):Fire(...)
end

function ctx.onState(fn: (Types.Snapshot) -> ()): () -> ()
	task.spawn(fn, ctx.State)
	local connection = stateChanged:Connect(fn)
	return function()
		connection:Disconnect()
	end
end

local function applyState(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	ctx.State = snapshot
	stateChanged:Fire(snapshot)
end

------------------------------------------------------------------------------------------------------------------
-- Toasts: the Toasts module shows them; until it exists (or if it breaks) a plain fallback does.
------------------------------------------------------------------------------------------------------------------

local fallbackHolder: Frame? = nil
local function fallbackToast(text: string)
	if not fallbackHolder then
		local gui = Instance.new("ScreenGui")
		gui.Name = "FallbackToasts"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = ctx.Player:WaitForChild("PlayerGui")
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 12)
		holder.Size = UDim2.new(0.9, 0, 0, 200)
		holder.BackgroundTransparency = 1
		holder.Parent = gui
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, 6)
		list.Parent = holder
		fallbackHolder = holder
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(340, 40)
	label.BackgroundColor3 = Color3.fromRGB(255, 245, 200)
	label.TextColor3 = Color3.fromRGB(74, 52, 42)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12) -- uirules: allow CornerLiteral (the fallback loads no Theme)
	corner.Parent = label
	label.Parent = fallbackHolder
	task.delay(2.5, function()
		local fade =
			TweenService:Create(label, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
end

function ctx.toast(text: string)
	if (listeners.Toast or 0) > 0 then
		ctx.fire("Toast", text)
	else
		fallbackToast(text)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Load the modules
------------------------------------------------------------------------------------------------------------------

local function loadModules(folderName: string, names: { string })
	local folder = script.Parent:FindFirstChild(folderName)
	if not folder then
		return
	end
	for _, name in names do
		local moduleScript = folder:FindFirstChild(name)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, result = pcall(require, moduleScript)
			if not ok then
				warn("[Client] " .. folderName .. "." .. name .. " failed to load: " .. tostring(result))
			elseif type(result) == "table" and type(result.init) == "function" then
				task.spawn(function()
					local initOk, err = xpcall(result.init, debug.traceback, ctx)
					if not initOk then
						warn("[Client] " .. folderName .. "." .. name .. ".init failed:\n" .. tostring(err))
					end
				end)
			end
		end
	end
end

loadModules("UI", UI_MODULES)
loadModules("Feel", FEEL_MODULES)

-- Wire the remotes after the modules have subscribed, so toasts queued during load reach the Toasts module.
Remotes.Toast.OnClientEvent:Connect(function(text: any)
	if type(text) == "string" then
		ctx.toast(text)
	end
end)

for _, name in FORWARDED_EVENTS do
	local remote = (Remotes :: any)[name] :: RemoteEvent
	remote.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			ctx.fire(name, payload)
		end
	end)
end

local gotPush = false
Remotes.State.OnClientEvent:Connect(function(snapshot: any)
	gotPush = true
	applyState(snapshot)
end)
task.spawn(function()
	local ok, snapshot = pcall(function()
		return Remotes.GetState:InvokeServer()
	end)
	-- A pushed snapshot is never older than the GetState answer, so a push wins.
	if ok and not gotPush then
		applyState(snapshot)
	end
end)
