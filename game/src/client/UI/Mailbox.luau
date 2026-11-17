--!strict
-- Mailbox (build plan Task 6): the letter and the daily goals.
--   init(ctx)   opens on ctx.fire("Open", "Mailbox") and ctx.fire("Open", "Goals")
-- Letter: when you join and the server says MailboxReady, an envelope drops in and opens into a thank-you
-- letter from patients you've treated (or a welcome note) with a 🎁 gift. Claim calls ClaimMailbox; the same gift
-- whether you were away a day or ten, and no streaks. It pops by itself only once per session, never over an open
-- panel. A player in the first-session tutorial gets it when the tutorial ends (the tutorial is quiet: design
-- §A6), and a brand-new player without the tutorial after their first patient is treated, so it never covers them.
-- Goals: up to Config.MaxBankedGoals banked goals with progress bars; a finished one gets a claim button that
-- calls ClaimGoal(index). Goals never expire.
-- All amounts shown are from Config and Data/DailyGoals, for display only; the server decides what you get.
-- Bus: fires "Claimed" ("Mailbox" | "Goal", id?) after the server says yes.
-- Look (UI/Modal's navy header, titles in words; the calm UI, docs/plan/2026-11-17-ui-direction.md §4 #10; Joshua,
-- memory-20261117-007): the letter is a popup: the 📬 (Icons.Door.Mail: one icon for mail, no 📭/💌 swap) sits on
-- turning rays while a gift waits (a reward moment), the gift amount is a Loud Unit (Kit.unit: the 💰 apart from
-- the outlined number), and "Open" is the Collect button (a plain Secondary "OK" once nothing waits). Goals: Kit.card
-- cards with no line, the goal's Art in a Kit.artTile, its words (Normal), a Kit.bar (navy) and its count, the
-- reward as one Soft line with one Unit ("💰 40 + 2 stars"); a finished goal's "Claim" is Collect. The gift and
-- the goals are free in-game cash and stars, never Robux.
-- Juice (depth update, design §4): the gift amount rolls up from 0 as the letter unfolds (Kit.countUp); a Collect
-- button whose reward waits shines and breathes (only one on screen at a time: Kit's motion budget); claiming bursts
-- confetti from it and flies the 💰 and ⭐ into the HUD; goal bars fill up and their counts roll while the panel is
-- open, and a goal that just filled pops its claim button in. Calm: no confetti, numbers simply set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Mailbox = {}

------------------------------------------------------------------------------------------------------------------
-- Pure: the words (tests/ProgressionPanels.spec loads the block with UI/Icons and a formatter)
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.TEXT = {
	Title = "Mail",
	GoalsTitle = "Goals",
	Open = "Open",
	Ok = "OK",
	Claim = "Claim",
	Busy = Icons.State.Waiting, -- alone in place of the button's label while the server answers
	Thanks = "Thank you, doctor!",
	Welcome = "Welcome to your clinic!",
	Empty = "New goals come each day",
	Oops = "Oops! Try again.",
	Got = "You got ",
}

-- The keeper's welcome when no patient has been treated yet: one Art emoji, not a sentence of them.
Pure.KEEPER = "🏡"

-- Six words or fewer, in words. The kinds keep their saved ids ("Cure"...); the words say treat.
function Pure.goalText(wings: any, def: any): string
	if def.Kind == "Cure" then
		return "Treat " .. def.Target .. " patients"
	elseif def.Kind == "CureNight" then
		return "Treat " .. def.Target .. " night patients"
	elseif def.Kind == "Make" then
		return "Make " .. def.Target .. " treatments"
	elseif def.Kind == "CureWing" then
		local wing = def.Wing and type(wings) == "table" and rawget(wings, def.Wing)
		return "Treat "
			.. def.Target
			.. (if type(wing) == "table" then " " .. tostring(wing.Name) else "")
			.. " patients"
	end
	return tostring(def.Icon)
end

-- What a goal pays, with ONE Unit: "💰 40 + 2 stars" (or "💰 40", or "2 stars").
function Pure.rewardText(def: any, format: (n: number) -> string): string
	local reward = if type(def) == "table" and type(def.Reward) == "table" then def.Reward else {}
	local cash = if type(reward.Cash) == "number" then reward.Cash else 0
	local stars = if type(reward.Stars) == "number" then reward.Stars else 0
	local parts = {}
	if cash > 0 then
		table.insert(parts, Icons.unit("Cash", format(cash)))
	end
	if stars > 0 then
		table.insert(parts, stars .. (if stars == 1 then " star" else " stars"))
	end
	return table.concat(parts, " + ")
end
-- PURE-END

Mailbox.Pure = Pure

local AUTO_POP_DELAY = 2 -- seconds after the save loads, so the world is on screen first
local FIRST_CURE_DELAY = 4 -- a new player's letter: after the first cure's sparkle and NEW PAGE banner
local MAX_THANKS = 3

local function goalDef(data: any, id: string): any
	for _, def in data.DailyGoals do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function rewardText(def: any): string
	return Pure.rewardText(def, Hud.format)
end

------------------------------------------------------------------------------------------------------------------
-- The letter
------------------------------------------------------------------------------------------------------------------

local function buildLetter(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "Mailbox",
		Layer = "Popup",
		Title = Pure.TEXT.Title,
		MaxSize = Vector2.new(420, 440),
		Scale = Vector2.new(0.9, 0.92),
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.fromScale(0.5, 0)
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = modal.Body
	local list = Kit.list(content, Enum.FillDirection.Vertical, Theme.Space.PadCard)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(content, modal.Body)

	-- The envelope, on rays while a gift waits (a holder, so the rays sit behind it).
	local envelopeHolder = Instance.new("Frame")
	envelopeHolder.Name = "Envelope"
	envelopeHolder.BackgroundTransparency = 1
	envelopeHolder.LayoutOrder = 1
	envelopeHolder.Size = UDim2.fromOffset(84, 84)
	envelopeHolder.Parent = content
	local rays = Kit.rays(envelopeHolder, Theme.Colors.Cash)
	rays.Visible = false
	local envelope = Kit.label({
		Name = "Icon",
		Text = Icons.Door.Mail,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = envelopeHolder,
	})

	-- The letter: a pale gold note (gold = your gift; a fill, no line) with the faces of patients who say thanks.
	local note = Instance.new("Frame")
	note.Name = "Letter"
	note.LayoutOrder = 2
	note.BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.82)
	note.BorderSizePixel = 0
	note.Size = UDim2.new(1, -Theme.Space.Step[5], 0, 120)
	Kit.corner(note, Theme.Radius.Medium)
	note.Parent = content
	local message = Kit.label({
		Name = "Message",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = note,
	})
	Kit.textLimit(message, Theme.TextSize.Button)
	local faces = Instance.new("Frame")
	faces.Name = "Faces"
	faces.BackgroundTransparency = 1
	faces.AnchorPoint = Vector2.new(0.5, 1)
	faces.Position = UDim2.new(0.5, 0, 1, -8)
	faces.Size = UDim2.new(1, -20, 0, 66)
	faces.Parent = note

	-- The gift: a Loud Unit (the 💰 apart from its gold outlined number: an emoji can't be outlined).
	local giftRow, gift = Kit.unit({
		Name = "Gift",
		Icon = Icons.Unit.Cash,
		Text = "0",
		Voice = "Loud",
		Px = Theme.TextSize.Number,
		LayoutOrder = 3,
		Parent = content,
	})
	gift.TextColor3 = Theme.Colors.Cash

	local claim = Kit.button({
		Name = "Claim",
		Kind = "Collect",
		Text = Pure.TEXT.Open,
		TextSize = Theme.TextSize.Title,
		LayoutOrder = 4,
		Size = UDim2.fromOffset(220, 64),
		Parent = content,
	})
	Kit.shine(claim)
	modal.Focus = claim
	local stopBreath: (() -> ())? = nil
	local function breathe(on: boolean)
		if on and not stopBreath then
			stopBreath = Kit.breathing(claim)
		elseif not on and stopBreath then
			stopBreath()
			stopBreath = nil
		end
	end
	local function giftText(n: number): string
		return Hud.format(math.floor(n + 0.5))
	end

	-- The rays turn only while the letter is open and a gift waits.
	local function syncRays()
		rays.Visible = modal.isOpen() and ctx.State.MailboxReady == true
	end

	local function drawFaces(state: Types.Snapshot)
		faces:ClearAllChildren()
		local row = Kit.list(faces, Enum.FillDirection.Horizontal, Theme.Space.Line)
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		local thanked = 0
		for _, patientId in data.Patients.Order do
			if thanked >= MAX_THANKS then
				break
			end
			local entry = state.Book and state.Book[patientId]
			if entry and (entry.Cured or 0) > 0 then
				thanked += 1
				local holder = Instance.new("Frame")
				holder.Name = patientId
				holder.LayoutOrder = thanked
				holder.BackgroundColor3 = Theme.Colors.Well
				holder.BorderSizePixel = 0
				holder.Size = UDim2.fromOffset(60, 60)
				Kit.corner(holder, Theme.Radius.Round)
				local portrait = Hud.portrait(data.Patients[patientId].Look)
				portrait.AnchorPoint = Vector2.new(0.5, 0.5)
				portrait.Position = UDim2.fromScale(0.5, 0.5)
				portrait.Size = UDim2.fromScale(0.9, 0.9)
				portrait.Parent = holder
				Kit.label({
					Name = "Heart",
					Text = "💛",
					TextScaled = true,
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, 4, 1, 4),
					Size = UDim2.fromOffset(24, 24),
					ZIndex = 3,
					Parent = holder,
				})
				holder.Parent = faces
			end
		end
		if thanked == 0 then
			Kit.label({
				Name = "Keeper",
				Text = Pure.KEEPER,
				TextScaled = true,
				Size = UDim2.new(1, 0, 0, 50),
				Parent = faces,
			})
		end
		return thanked
	end

	local function render(state: Types.Snapshot)
		local ready = state.MailboxReady == true
		note.Visible = ready
		giftRow.Visible = ready
		-- (A roll already heading to this amount carries on: see animateOpen.)
		Kit.countUp(gift, ctx.Config.MailboxGiftCash or 0, giftText, 0)
		claim.Text = if ready then Pure.TEXT.Open else Pure.TEXT.Ok
		-- A gift waiting: the Collect "Open!" (it shines and breathes). Nothing waiting: a plain Secondary OK.
		Kit.setRole(claim, if ready then "Collect" else "Secondary")
		breathe(ready)
		if ready then
			message.Text = if drawFaces(state) > 0 then Pure.TEXT.Thanks else Pure.TEXT.Welcome
		end
		syncRays()
	end

	-- The envelope drops in, wiggles, and then the letter unfolds.
	local function animateOpen()
		if Hud.calm() then
			return
		end
		local scale = envelope:FindFirstChild("Drop") :: UIScale?
		if not scale then
			local created = Instance.new("UIScale")
			created.Name = "Drop"
			created.Parent = envelope
			scale = created
		end
		local dropScale = scale :: UIScale
		dropScale.Scale = 0.3
		envelope.Rotation = -20
		TweenService:Create(dropScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		task.spawn(function()
			for _, angle in { 14, -10, 6, 0 } do
				local wiggle = TweenService:Create(envelope, TweenInfo.new(0.12), { Rotation = angle })
				wiggle:Play()
				wiggle.Completed:Wait()
			end
		end)
		if note.Visible then
			Hud.pop(note, 0.6)
			-- The gift amount rolls up from 0 once the letter unfolds.
			Kit.countUp(gift, 0, giftText, 0)
			task.delay(0.35, function()
				if giftRow.Visible then
					Kit.countUp(gift, ctx.Config.MailboxGiftCash or 0, giftText, 0.7)
				end
			end)
		end
	end

	local claiming = false
	claim.Activated:Connect(function()
		if claiming then
			return
		end
		if ctx.State.MailboxReady ~= true then
			modal.close()
			return
		end
		claiming = true
		claim.Text = Pure.TEXT.Busy
		claim.Interactable = false
		Kit.setRole(claim, "Secondary")
		local ok, reply = Hud.ask(ctx.Remotes.ClaimMailbox)
		claiming = false
		claim.Interactable = true
		if ok then
			ctx.fire("Claimed", "Mailbox")
			breathe(false)
			Kit.bump(giftRow)
			Kit.confetti(modal.Root, 24, UDim2.fromScale(0.5, 0.45))
			Hud.fly(giftRow, Icons.Unit.Cash, "Cash", 8)
			Hud.sound("Chime")
			if reply ~= "" then
				ctx.toast(reply)
			end
			task.delay(0.9, modal.close)
		else
			ctx.toast(if reply ~= "" then reply else Pure.TEXT.Oops)
			Hud.shake(claim)
			render(ctx.State)
		end
	end)

	local function open()
		render(ctx.State)
		modal.open()
		syncRays()
		animateOpen()
	end

	ctx.onState(function(state: Types.Snapshot)
		if not claiming then
			render(state)
		end
	end)
	ctx.on("ModalClosed", function(name: any)
		if name == "Mailbox" then
			syncRays()
		end
	end)
	return open, modal
end

------------------------------------------------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------------------------------------------------

type GoalRow = {
	Frame: Frame,
	Icon: TextLabel,
	Text: TextLabel,
	SetBar: (fraction: number, atMax: boolean?) -> (),
	Count: TextLabel,
	Reward: TextLabel,
	Claim: TextButton,
	Done: boolean, -- as last drawn, so the claim button springs in once when a goal fills
	Goal: string, -- the goal id drawn, so a new goal in the same row doesn't roll from the old one
}

local function buildGoals(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "Goals",
		Title = Pure.TEXT.GoalsTitle,
		MaxSize = Vector2.new(560, 460),
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
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
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, Theme.Space.PadCard)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll

	local empty = Kit.fact({
		Name = "Empty",
		Text = Pure.TEXT.Empty,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 40),
		Visible = false,
		Parent = modal.Body,
	})

	local rows: { GoalRow } = {}
	local claimingIndex: number? = nil
	local render: (state: Types.Snapshot) -> ()

	local function makeRow(index: number): GoalRow
		local pad = Theme.Space.PadCard
		local art = Theme.Calm.ArtTile
		local claimWidth = 124
		local frame = Kit.card({ Name = "Goal" .. index, LayoutOrder = index, Pad = false, Parent = scroll })
		frame.AutomaticSize = Enum.AutomaticSize.None
		frame.Size = UDim2.new(1, 0, 0, 92)

		local tile = Kit.artTile({
			Icon = "",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, pad, 0.5, 0),
			Parent = frame,
		})
		local icon = tile:FindFirstChild("Icon") :: TextLabel
		local left = pad * 2 + art
		local right = claimWidth + pad * 2
		local text = Kit.name({
			Name = "What",
			Text = "",
			Position = UDim2.fromOffset(left, pad - Theme.Space.Tight),
			Size = UDim2.new(1, -left - right, 0, Theme.TextSize.Body + Theme.Space.Tight),
			Parent = frame,
		})
		local countWidth = 56
		local _, setBar = Kit.bar({
			Name = "Bar",
			Position = UDim2.fromOffset(left, 44),
			Size = UDim2.new(1, -left - right - countWidth - Theme.Space.Line, 0, Theme.Calm.Bar),
			Parent = frame,
		})
		local count = Kit.fact({
			Name = "Count",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -right, 0, 44 + Theme.Calm.Bar / 2),
			Size = UDim2.fromOffset(countWidth, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local reward = Kit.fact({
			Name = "Reward",
			Text = "",
			Position = UDim2.fromOffset(left, 60),
			Size = UDim2.new(1, -left - right, 0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local claim = Kit.button({
			Name = "Claim",
			Kind = "Collect",
			Text = Pure.TEXT.Claim,
			TextSize = Theme.TextSize.Button,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -pad, 0.5, 0),
			Size = UDim2.fromOffset(claimWidth, 60),
			Parent = frame,
		})
		-- Collect: it shines and breathes only while it shows (a goal is done), one button at a time.
		Kit.shine(claim)
		Kit.breathing(claim)
		local row: GoalRow = {
			Frame = frame,
			Icon = icon,
			Text = text,
			SetBar = setBar,
			Count = count,
			Reward = reward,
			Claim = claim,
			Done = false,
			Goal = "",
		}

		claim.Activated:Connect(function()
			if claimingIndex then
				return
			end
			local goals = ctx.State.Daily and ctx.State.Daily.Goals or {}
			local goal = goals[index]
			local def = goal and goalDef(data, goal.Id)
			if not def or (goal.Progress or 0) < def.Target then
				Hud.shake(claim)
				return
			end
			claimingIndex = index
			claim.Text = Pure.TEXT.Busy
			claim.Interactable = false
			local ok, reply = Hud.ask(ctx.Remotes.ClaimGoal, index)
			claimingIndex = nil
			if ok then
				ctx.fire("Claimed", "Goal", def.Id)
				Hud.sound("Fanfare")
				local origin = claim.AbsolutePosition + claim.AbsoluteSize / 2 - modal.Root.AbsolutePosition
				Kit.confetti(modal.Root, 20, UDim2.fromOffset(origin.X, origin.Y))
				if (def.Reward.Cash or 0) > 0 then
					Hud.fly(claim, Icons.Unit.Cash, "Cash", 6)
				end
				if (def.Reward.Stars or 0) > 0 then
					Hud.fly(claim, Icons.Unit.Stars, "Stars", math.min(def.Reward.Stars, 5))
				end
				ctx.toast(if reply ~= "" then reply else Pure.TEXT.Got .. rewardText(def))
			else
				ctx.toast(if reply ~= "" then reply else Pure.TEXT.Oops)
				Hud.shake(claim)
			end
			claim.Interactable = true
			render(ctx.State)
		end)
		return row
	end

	render = function(state: Types.Snapshot)
		if claimingIndex then
			return
		end
		local goals = (state.Daily and state.Daily.Goals) or {}
		local shown = 0
		for index, goal in goals do
			local def = type(goal) == "table" and goalDef(data, goal.Id)
			if def then
				shown += 1
				local row = rows[index] or makeRow(index)
				rows[index] = row
				row.Frame.Visible = true
				local progress = math.clamp(goal.Progress or 0, 0, def.Target)
				local done = progress >= def.Target
				-- While the panel is open, the same goal's count rolls and its bar fills; otherwise they're set.
				local live = modal.isOpen() and row.Goal == def.Id and not Hud.calm()
				row.Goal = def.Id
				row.Icon.Text = def.Icon
				row.Text.Text = Pure.goalText(data.Wings, def)
				local target = def.Target
				Kit.countUp(row.Count, progress, function(n: number): string
					return math.floor(n + 0.5) .. "/" .. target
				end, if live then nil else 0)
				row.Reward.Text = rewardText(def)
				row.SetBar(Kit.Juice.barFraction(progress, def.Target)) -- Kit.bar slides there while it's on screen
				row.Claim.Visible = done
				row.Claim.Text = Pure.TEXT.Claim
				row.Frame.BackgroundColor3 = if done then Kit.lighten(Theme.Colors.Collect, 0.86) else Theme.Colors.Card
				if done and not row.Done then
					Kit.punch(row.Claim, 0.4, Theme.Tween.PopIn)
					if live then
						Hud.sound("Sparkle")
					end
				end
				row.Done = done
			elseif rows[index] then
				rows[index].Frame.Visible = false
			end
		end
		for index = #goals + 1, #rows do
			rows[index].Frame.Visible = false
		end
		empty.Visible = shown == 0
		-- Gamepad: land on the first claim button, if any.
		modal.Focus = modal.CloseButton
		for _, row in rows do
			if row.Frame.Visible and row.Claim.Visible then
				modal.Focus = row.Claim
				break
			end
		end
	end
	ctx.onState(render)

	return function()
		render(ctx.State)
		modal.open()
	end
end

------------------------------------------------------------------------------------------------------------------

function Mailbox.init(ctx: Types.Ctx)
	local initial = ctx.State
	local openLetter = buildLetter(ctx)
	local openGoals = buildGoals(ctx)

	ctx.on("Open", function(name: any)
		if name == "Mailbox" then
			openLetter()
		elseif name == "Goals" then
			openGoals()
		end
	end)

	-- Pop the letter once, the first time the server says it's ready this session. A player in the first-session
	-- tutorial gets it when the tutorial ends (its last step points at the 📖, so the letter comes after). A
	-- brand-new player without the tutorial (nothing cured yet) gets it after their first cure: on join their first
	-- patient and the Guide arrow arrive at once, and a dimmed letter would cover them and block the thumbstick.
	local popped = false
	local waited = false
	ctx.onState(function(state: Types.Snapshot)
		if popped or state == initial or state.MailboxReady ~= true then
			return
		end
		if TutorialLogic.active(state.Tutorial) then
			waited = true -- a later snapshot with the tutorial done pops it
			return
		end
		if (state.Cured or 0) < 1 and state.PlotIndex ~= nil then
			waited = true -- a later snapshot with Cured >= 1 pops it (without a clinic, it pops now)
			return
		end
		popped = true
		task.delay(if waited then FIRST_CURE_DELAY else AUTO_POP_DELAY, function()
			-- Never over an open panel or popup (the 📖 Book, say): it waits until they close it.
			while Hud.isOpen() do
				task.wait(0.5)
			end
			if ctx.State.MailboxReady == true then
				openLetter()
			end
		end)
	end)
end

return Mailbox
