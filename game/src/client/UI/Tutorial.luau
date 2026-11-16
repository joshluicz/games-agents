--!strict
-- Tutorial (client): the first-session step card, its pointer, the welcome title card and the first-join camera
-- sweep (docs/plan/2026-11-16-first-session-design.md). The server owns the step (Snapshot.Tutorial, kept by
-- Server/Tutorial); this module only shows it, and the only thing it ever asks is TutorialAck, which can only move
-- the server past the welcome card.
--   init(ctx)
--
-- The card sits at the bottom centre, just above the HUD's hands and buttons (clear of the thumbstick and the jump
-- button). Icon first, 8 words or fewer. It never takes a touch except on the welcome card, and it hides while a
-- panel is open (the pointer stays) and for good once the tutorial is done.
--   1 👋 Welcome to your clinic, Doctor!            tap it, or WELCOME_SECONDS: TutorialAck
--   2 🤧 A patient! The bubble shows what's wrong.  the Guide's pin over the first patient (Guide.setSteer)
--   3 🧪 Hold at the potion table!                   + ⌨️ Hold E / 👆 Tap and hold / 🎮 Hold X; the Guide's arrow
--   4 🏥 Take it to the Counter. Treat!              the Guide's arrow to the Counter
--   5 🛏️ Resting… Cured! 🎉                         the pin over the resting patient, on its bed
--   6 💪 Cure 2 more! (n/2)                          the Guide's usual arrows (n = Snapshot.TutorialCures)
--   7 🛒 Spend 💰 in the Shop!                       a bouncing 👇 and a ring on the 🛒 button, then (Shop open)
--                                                    on the cheapest upgrade's buy button
--   8 📖 Collect every creature in your Book!        the 👇 on the 📖 button; tapping it hides the card (the
--                                                    server finishes the tutorial a few seconds later)
-- Nothing is timed against the player: the two timers only move the tutorial on by itself.
--
-- The first-ever join (step 1, once per session): when your character reaches your clinic, a CAMERA_SWEEP_SECONDS
-- camera sweep over the clinic under a title card "🏥 Welcome to Cure a Creature!", then the normal camera and the
-- step 1 card. Reduced motion (Kit.reducedMotion): no sweep, just the title card. Your controls rest during the
-- sweep. And for every owner (done players too): whenever your character arrives at your clinic (on joining or
-- respawning), the camera turns to look the way the character faces, at the clinic (design §A1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local Logic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

-- Guide and Shop are optional: if one of them failed to load, the tutorial still runs without its pointer.
local function optional(name: string): any
	local ok, result = pcall(function()
		return require(script.Parent:WaitForChild(name, 5) :: ModuleScript)
	end)
	return if ok and type(result) == "table" then result else nil
end
local Guide = optional("Guide")
local Shop = optional("Shop")

local Tutorial = {}

local CAMERA_SWEEP_SECONDS = 3
local TITLE_STILL_SECONDS = 2.6 -- reduced motion: the title card alone
local HOME_STUDS = 14 -- your character this close to your clinic's QueueStart = arrived
local HOME_WAIT_SECONDS = 4
local CARD_GAP = 8 -- px between the card and the HUD's bottom cluster
local FINGER_ROOM = 64 -- extra px the card rises while the 👇 points at a bottom button
local CAMERA_BACK = 13 -- the camera behind your character after a sweep or on arrival
local CAMERA_UP = 5.5

type Line = { Icon: string, Text: string, Color: Color3 }
local LINES: { [number]: Line } = {
	[Logic.WELCOME] = { Icon = "👋", Text = "Welcome to your clinic, Doctor!", Color = Theme.Colors.Primary },
	[Logic.PATIENT] = { Icon = "🤧", Text = "A patient! The bubble shows what's wrong.", Color = Theme.Colors.Pink },
	[Logic.MAKE] = { Icon = "🧪", Text = "Hold at the potion table!", Color = Theme.Colors.Purple },
	[Logic.TREAT] = { Icon = "🏥", Text = "Take it to the Counter. Treat!", Color = Theme.Colors.Good },
	[Logic.REST] = { Icon = "🛏️", Text = "Resting… Cured! 🎉", Color = Theme.Colors.Cyan },
	[Logic.MORE] = { Icon = "💪", Text = "Cure %d more! (%d/%d)", Color = Theme.Colors.Primary },
	[Logic.SHOP] = { Icon = "🛒", Text = "Spend 💰 in the Shop!", Color = Theme.Colors.Pink },
	[Logic.BOOK] = { Icon = "📖", Text = "Collect every creature in your Book!", Color = Theme.Colors.Purple },
}

local player = Players.LocalPlayer

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

-- True when gui is on screen: it and every GuiObject above it are Visible, and its ScreenGui is enabled.
local function isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function deviceHint(): string
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if not ok then
		-- An engine without PreferredInput: a touch screen without a keyboard is a phone or tablet.
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			return "👆 Tap and hold"
		end
		return if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
			then "🎮 Hold X"
			else "⌨️ Hold E"
	end
	if preferred == Enum.PreferredInput.Touch then
		return "👆 Tap and hold"
	elseif preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad then
		return "🎮 Hold X"
	end
	return "⌨️ Hold E"
end

local function plotModel(state: Types.Snapshot): Model?
	local clinics = Workspace:FindFirstChild("Clinics")
	local index = state.PlotIndex
	local plot = if clinics and type(index) == "number" then clinics:FindFirstChild("Plot_" .. index) else nil
	return if plot and plot:IsA("Model") then plot else nil
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Waits (up to `timeout`) for your character to stand at your clinic: the server moves it there on joining and on
-- respawning. Returns its root part, or nil.
local function waitForHome(plot: Model, timeout: number): BasePart?
	local started = os.clock()
	while os.clock() - started < timeout do
		local queue = plot:FindFirstChild("QueueStart")
		local root = rootOf()
		if root and queue and queue:IsA("BasePart") then
			local flat = (root.Position - queue.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude < HOME_STUDS then
				return root
			end
		end
		task.wait(0.1)
	end
	return nil
end

-- The camera just behind your character, looking the way it faces (a little down, at the clinic).
local function behind(root: BasePart): CFrame
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	return CFrame.lookAt(focus - look * CAMERA_BACK + Vector3.new(0, CAMERA_UP, 0), focus + look * 6)
end

-- The player's own controls rest during the sweep (the standard PlayerModule; skipped if it isn't there).
local function setControls(on: boolean)
	pcall(function()
		local scripts = player:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module and module:IsA("ModuleScript") then
			local controls = (require(module) :: any):GetControls()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- The welcome: title card and camera sweep
------------------------------------------------------------------------------------------------------------------

-- The title card: a pink candy ribbon with the game's name, on turning rays (still with reduced motion).
local function showTitle(seconds: number)
	local gui = Kit.screen("TutorialTitle", Theme.DisplayOrder.Popup)
	local holder = Instance.new("Frame")
	holder.Name = "Title"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.36)
	holder.Size = UDim2.new(0.86, 0, 0, 140)
	holder.BackgroundTransparency = 1
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 140)
	limit.Parent = holder
	holder.Parent = gui

	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 1)
	ribbon.Position = UDim2.fromScale(0.5, 1)
	ribbon.Size = UDim2.new(1, 0, 0, 84)
	ribbon.BackgroundColor3 = Kit.lighten(Theme.Colors.Pink, 0.08)
	ribbon.BorderSizePixel = 0
	Kit.corner(ribbon, Theme.Size.CornerLarge)
	Kit.stroke(ribbon, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(ribbon)
	Kit.gloss(ribbon, 18)
	ribbon.ZIndex = 2 -- over the sunburst behind the icon
	ribbon.Parent = holder
	local text = Kit.label({
		Name = "Text",
		Text = "Welcome to Cure a Creature!",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -36, 0, 52),
		ZIndex = 2,
		Parent = ribbon,
	})
	Kit.outline(text, Theme.Size.Stroke)
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = Theme.TextSize.Big
	textLimit.MinTextSize = Theme.TextSize.Small
	textLimit.Parent = text
	-- The clinic icon on top of the ribbon, on a little sunburst (behind it, ZIndex 0).
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.fromScale(0.5, 0)
	badge.Size = UDim2.fromOffset(58, 58)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 1
	badge.Parent = holder
	Kit.rays(badge, Theme.Colors.Cash)
	Kit.label({
		Name = "Icon",
		Text = "🏥",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = badge,
	})

	Kit.popIn(holder)
	Hud.sound("Fanfare", 0.8)
	task.wait(seconds)
	Kit.popOut(holder, function()
		gui:Destroy()
	end)
end

-- Flies the camera from high above the street, round the clinic, down to just behind your character.
local function sweep(plot: Model, finish: CFrame, seconds: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local pivot = plot:GetPivot()
	local counter = plot:FindFirstChild("Counter")
	local look = if counter and counter:IsA("BasePart") then counter.Position else pivot.Position
	-- Plot-local -Z is toward the street: start high over the street and to the left, swing round to the right.
	local p0 = (pivot * CFrame.new(-30, 34, -66)).Position
	local p1 = (pivot * CFrame.new(26, 20, -40)).Position
	local p2 = finish.Position
	local f0 = look
	local f2 = finish.Position + finish.LookVector * 10
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	while true do
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local e = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local a = p0:Lerp(p1, e)
		local b = p1:Lerp(p2, e)
		camera.CFrame = CFrame.lookAt(a:Lerp(b, e), f0:Lerp(f2, e))
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CFrame = finish
end

------------------------------------------------------------------------------------------------------------------

function Tutorial.init(ctx: Types.Ctx)
	local data = ctx.Data :: any

	--------------------------------------------------------------------------------------------------------------
	-- The card
	--------------------------------------------------------------------------------------------------------------
	local cardGui = Kit.screen("TutorialCard", Theme.DisplayOrder.Hud + 2)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -Theme.Size.Margin)
	card.Size = UDim2.new(0.5, 0, 0, 84)
	card.BackgroundColor3 = Theme.Colors.Paper
	card.BorderSizePixel = 0
	card.Active = false -- touches go through to the world and the thumbstick
	card.Visible = false
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MinSize = Vector2.new(300, 0)
	cardLimit.MaxSize = Vector2.new(440, 200)
	cardLimit.Parent = card
	Kit.corner(card, Theme.Size.CornerLarge)
	Kit.stroke(card, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	local paper = Instance.new("UIGradient")
	paper.Rotation = 90
	paper.Color = ColorSequence.new(Theme.Colors.Paper, Theme.Colors.PaperEdge)
	paper.Parent = card
	card.Parent = cardGui

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, 12, 0.5, 0)
	tile.Size = UDim2.fromOffset(58, 58)
	tile.BorderSizePixel = 0
	Kit.corner(tile, Theme.Size.Corner)
	Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(tile)
	Kit.gloss(tile, 7)
	tile.Parent = card
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 2,
		Parent = tile,
	})

	local line = Kit.label({
		Name = "Line",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 82, 0.5, 0),
		Size = UDim2.new(1, -96, 0, 60),
		Parent = card,
	})
	local lineLimit = Instance.new("UITextSizeConstraint")
	lineLimit.MaxTextSize = 28
	lineLimit.MinTextSize = Theme.TextSize.Small
	lineLimit.Parent = line

	-- Step 3's "how to hold": a small candy chip under the line.
	local hint = Kit.label({
		Name = "Hint",
		Text = "",
		Outlined = true,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		BackgroundColor3 = Kit.lighten(Theme.Colors.Secondary, 0.08),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 82, 1, -10),
		Size = UDim2.fromOffset(168, 32),
		Visible = false,
		Parent = card,
	})
	Kit.corner(hint, 16)
	Kit.stroke(hint, Theme.Colors.Outline, 2.5)

	-- The welcome card can be tapped (and only that one: the button is hidden on every other step).
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 5
	tap.Visible = false
	tap.Parent = card

	--------------------------------------------------------------------------------------------------------------
	-- The UI pointer (steps 7 and 8): a ring round the target and a bouncing 👇 above it, over panels
	--------------------------------------------------------------------------------------------------------------
	local pointerGui = Kit.screen("TutorialPointer", Theme.DisplayOrder.Panel + 5)
	local ringOuter = Instance.new("Frame")
	ringOuter.Name = "Ring"
	ringOuter.BackgroundTransparency = 1
	ringOuter.Visible = false
	Kit.corner(ringOuter, Theme.Size.Corner + 6)
	Kit.stroke(ringOuter, Theme.Colors.Outline, 8)
	ringOuter.Parent = pointerGui
	local ringInner = Instance.new("Frame")
	ringInner.Name = "Glow"
	ringInner.BackgroundTransparency = 1
	ringInner.Size = UDim2.fromScale(1, 1)
	Kit.corner(ringInner, Theme.Size.Corner + 6)
	Kit.stroke(ringInner, Theme.Colors.Cash, 4)
	ringInner.Parent = ringOuter
	local finger = Kit.label({
		Name = "Finger",
		Text = "👇",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(54, 54),
		Visible = false,
		Parent = pointerGui,
	})

	--------------------------------------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------------------------------------
	local welcome: "None" | "Intro" | "Card" = "None"
	local acking = false
	local bookSeen = false
	local shownStep = 0 -- the step the card shows (0 = hidden)
	local shownText = ""

	local function ack()
		if acking then
			return
		end
		acking = true
		task.spawn(function()
			local ok = Hud.ask(ctx.Remotes.TutorialAck)
			if not ok then
				acking = false -- tap again (the server also moves on by itself)
			end
		end)
	end
	tap.Activated:Connect(function()
		Kit.bump(card)
		ack()
	end)

	local function cheapestUpgrade(): string?
		local best: string?, bestPrice = nil, math.huge
		local levels = ctx.State.Upgrades or {}
		for _, id in data.Upgrades.Order do
			local price = Prices.upgradePrice(data.Upgrades, id, levels[id] or 0)
			if price and price < bestPrice then
				best, bestPrice = id, price
			end
		end
		return best
	end

	-- The step the card shows right now, or nil for no card.
	local function cardStep(): number?
		local state = ctx.State
		local step = state.Tutorial
		if not Logic.active(step) or state.PlotIndex == nil or Hud.isOpen() then
			return nil
		end
		if step == Logic.WELCOME and welcome ~= "Card" then
			return nil -- the title card and sweep come first
		end
		if step == Logic.BOOK and bookSeen then
			return nil
		end
		return step
	end

	local function render()
		local step = cardStep()
		if not step then
			card.Visible = false
			shownStep, shownText = 0, ""
			return
		end
		local entry = LINES[step]
		local text = entry.Text
		if step == Logic.MORE then
			local done = math.clamp(ctx.State.TutorialCures or 0, 0, Logic.MORE_CURES)
			text = string.format(entry.Text, Logic.MORE_CURES, done, Logic.MORE_CURES)
		end
		local hintText = if step == Logic.MAKE then deviceHint() else ""
		icon.Text = entry.Icon
		line.Text = text
		hint.Text = hintText
		hint.Visible = hintText ~= ""
		card.Size = UDim2.new(0.5, 0, 0, if hintText ~= "" then 112 else 84)
		line.Position = UDim2.new(0, 82, if hintText ~= "" then 0.36 else 0.5, 0)
		line.Size = UDim2.new(1, -96, 0, if hintText ~= "" then 52 else 60)
		tile.BackgroundColor3 = Kit.lighten(entry.Color, 0.08)
		tap.Visible = step == Logic.WELCOME
		if step ~= shownStep then
			Kit.popIn(card) -- a new step (or back after a panel closed): pops in (still with reduced motion)
			Hud.sound("Pop", 0.8)
		elseif text ~= shownText then
			Kit.bump(tile) -- the same step, a new count (6: "1/2")
		end
		shownStep, shownText = step, text
		card.Visible = true
	end

	--------------------------------------------------------------------------------------------------------------
	-- Following the layout every frame: the card above the HUD's bottom cluster, the pointer on its target
	--------------------------------------------------------------------------------------------------------------
	local function clusterTop(): number?
		local top: number? = nil
		for _, name in { "Hands", "Shop", "Book", "Mailbox", "Goals" } do
			local piece = Hud.target(name)
			if piece and isShown(piece) then
				local y = piece.AbsolutePosition.Y
				top = if top then math.min(top, y) else y
			end
		end
		return top
	end

	local function uiTarget(): GuiObject?
		local step = ctx.State.Tutorial
		if step == Logic.SHOP then
			if Hud.isOpen("Shop") then
				local id = cheapestUpgrade()
				local button = if Shop and id then Shop.upgradeButton(id) else nil
				if button and isShown(button) then
					return button
				end
				local tab = if Shop then Shop.tabButton("Upgrades") else nil
				return if tab and isShown(tab) then tab else nil
			end
			return if Hud.isOpen() then nil else Hud.target("Shop")
		elseif step == Logic.BOOK and not bookSeen then
			return if Hud.isOpen() then nil else Hud.target("Book")
		end
		return nil
	end

	RunService.RenderStepped:Connect(function()
		local target = if Logic.active(ctx.State.Tutorial) then uiTarget() else nil
		if card.Visible then
			local top = clusterTop()
			-- While the 👇 points at a bottom button, lift the card clear of it so the finger never covers the words.
			local fingerRoom = if target and not Hud.isOpen() then FINGER_ROOM else 0
			local bottom = if top
				then top - cardGui.AbsolutePosition.Y - CARD_GAP - fingerRoom
				else cardGui.AbsoluteSize.Y - Theme.Size.Margin
			card.Position = UDim2.new(0.5, 0, 0, bottom)
		end

		if target and isShown(target) and target.AbsoluteSize.X > 0 then
			local at = target.AbsolutePosition - pointerGui.AbsolutePosition
			local size = target.AbsoluteSize
			ringOuter.Position = UDim2.fromOffset(at.X - 7, at.Y - 7)
			ringOuter.Size = UDim2.fromOffset(size.X + 14, size.Y + 14)
			local bob = if Kit.reducedMotion() then 0 else math.abs(math.sin(os.clock() * 4)) * 10
			finger.Position = UDim2.fromOffset(at.X + size.X / 2, at.Y - 10 - bob)
			ringOuter.Visible = true
			finger.Visible = true
		else
			ringOuter.Visible = false
			finger.Visible = false
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- The world pointer: the Guide's pin and arc (steps 2 and 5 here; 3, 4 and 6 are its usual arrows)
	--------------------------------------------------------------------------------------------------------------
	local function patients(plot: Instance): { Model }
		local found: { Model } = {}
		local folder = plot:FindFirstChild("Patients")
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child.PrimaryPart then
					table.insert(found, child)
				end
			end
		end
		return found
	end

	-- The pin floats just over the patient's badge, so the badge itself stays readable.
	local function pinOver(patient: Model, pinIcon: string, color: Color3): any
		local root = patient.PrimaryPart :: BasePart
		local anchor = root:FindFirstChild("IconAnchor")
		local height = if anchor and anchor:IsA("Attachment") then anchor.WorldPosition.Y + 2.6 else root.Position.Y + 6
		return { Part = root, Icon = pinIcon, Color = color, Height = height }
	end

	if Guide then
		Guide.setSteer(function(plot: Instance): any
			local step = ctx.State.Tutorial
			if not Logic.active(step) then
				return nil -- done: the Guide as it always was
			end
			if step == Logic.WELCOME or step >= Logic.SHOP then
				return false
			elseif step == Logic.PATIENT then
				for _, patient in patients(plot) do
					if patient:GetAttribute("QueueIndex") == 1 then
						return pinOver(patient, "👀", Theme.Colors.Pink)
					end
				end
				return false
			elseif step == Logic.REST then
				for _, patient in patients(plot) do
					local state = patient:GetAttribute("State")
					if state == "Treated" or state == "Recovering" then
						return pinOver(patient, "🛏️", Theme.Colors.Cyan)
					end
				end
				return false
			end
			return nil -- 3, 4 and 6: the Guide's usual arrows
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Arriving at your clinic: the welcome (first-ever join), or just the camera turned to the clinic
	--------------------------------------------------------------------------------------------------------------
	local arriving = 0
	local function intro(plot: Model)
		local root = waitForHome(plot, HOME_WAIT_SECONDS)
		if root and not Kit.reducedMotion() then
			setControls(false)
			local finish = behind(root)
			task.spawn(showTitle, CAMERA_SWEEP_SECONDS + 0.4)
			local ok, err = pcall(sweep, plot, finish, CAMERA_SWEEP_SECONDS)
			if not ok then
				warn("[Tutorial] camera sweep: " .. tostring(err))
				local camera = Workspace.CurrentCamera
				if camera then
					camera.CameraType = Enum.CameraType.Custom
				end
			end
			setControls(true)
			task.wait(0.5)
		else
			local camera = Workspace.CurrentCamera
			if root and camera then
				camera.CFrame = behind(root)
			end
			showTitle(TITLE_STILL_SECONDS)
		end
		welcome = "Card"
		render()
		task.delay(Logic.WELCOME_SECONDS, function()
			if ctx.State.Tutorial == Logic.WELCOME then
				ack()
			end
		end)
	end

	-- Every owner: once the server has moved your character to your clinic, turn the camera to the clinic.
	local function arrive()
		arriving += 1
		local mine = arriving
		local state = ctx.State
		local plot = plotModel(state)
		if not plot then
			return
		end
		if state.Tutorial == Logic.WELCOME and welcome == "None" then
			welcome = "Intro"
			intro(plot)
			return
		end
		if welcome == "Intro" then
			return -- the sweep handles the camera
		end
		local root = waitForHome(plot, HOME_WAIT_SECONDS)
		local camera = Workspace.CurrentCamera
		if root and camera and mine == arriving and camera.CameraType == Enum.CameraType.Custom then
			camera.CFrame = behind(root)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Wiring
	--------------------------------------------------------------------------------------------------------------
	local hadPlot = false
	ctx.onState(function(state: Types.Snapshot)
		-- The first server snapshot with your clinic starts the arrival (and the welcome). The client's default
		-- snapshot says Tutorial 0, so it never counts.
		local known = type(state.Tutorial) == "number" and state.Tutorial > 0
		local hasPlot = known and state.PlotIndex ~= nil
		if hasPlot and not hadPlot then
			task.spawn(arrive)
		end
		hadPlot = hasPlot
		render()
	end)

	player.CharacterAdded:Connect(function()
		if hadPlot and welcome ~= "Intro" then
			task.spawn(arrive)
		end
	end)

	ctx.on("Open", function(name: any)
		if name == "Book" and ctx.State.Tutorial == Logic.BOOK then
			bookSeen = true
		end
		render()
	end)
	ctx.on("ModalOpened", function()
		render()
	end)
	ctx.on("ModalClosed", function()
		render()
	end)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(render)
	end)
end

return Tutorial
