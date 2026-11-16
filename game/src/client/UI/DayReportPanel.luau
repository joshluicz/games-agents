--!strict
-- DayReportPanel (build plan Task 6): the end-of-day card, popped when the server sends DayReport (at night's
-- end). A big count of patients cured, ⭐ gained, the new Book pages as faces, and the one clear "next goal"
-- with a bar showing how close it is (⭐ toward its stars, then 💰 toward its price) and a 🛒 button that opens
-- the Shop on it. It closes by itself after AUTO_CLOSE seconds.
--   init(ctx)   listens to the DayReport remote
-- It doesn't dim the screen or grab gamepad focus: it arrives on its own while you play, so it never blocks you.
-- A day with nothing cured shows nothing (no "you did nothing" screen).
-- Look (candy pop, memory-20261116-007): an orange header; the count is big gold outlined display text on turning
-- rays and springs when it lands; candy chips for ⭐ and 📖; new faces in outlined bubbles that pop in one by one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local DayReportPanel = {}

local ACCENT = Theme.Colors.Primary
local AUTO_CLOSE = 8
local MAX_FACES = 5
local FACE_STAGGER = 0.08 -- seconds between each new face's pop

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = label
end

-- The report comes from the server, but check its shape anyway so a bad one can't break the UI.
local function clean(report: any): Types.DayReportInfo?
	if type(report) ~= "table" then
		return nil
	end
	local pages = {}
	if type(report.NewPages) == "table" then
		for _, id in report.NewPages do
			if type(id) == "string" then
				table.insert(pages, id)
			end
		end
	end
	local nextGoal = if type(report.Next) == "table" then report.Next else {}
	return {
		Cured = if type(report.Cured) == "number" then math.max(0, math.floor(report.Cured)) else 0,
		NewPages = pages,
		StarsGained = if type(report.StarsGained) == "number" then math.max(0, math.floor(report.StarsGained)) else 0,
		Next = {
			Kind = if type(nextGoal.Kind) == "string" then nextGoal.Kind else "None",
			Id = if type(nextGoal.Id) == "string" then nextGoal.Id else "",
			Icon = if type(nextGoal.Icon) == "string" then nextGoal.Icon else "",
		},
	}
end

-- The next goal's bar: Clinic Stars toward a room's StarsNeeded, then cash toward its price (or an upgrade's next
-- price). Returns which it measures ("Stars" | "Cash") and how full it is, 0..1. Display only.
local function progressTo(state: Types.Snapshot, room: any, upgrade: any, id: string): (string, number)
	local stars = state.Stars or 0
	local cash = state.Cash or 0
	local function ratio(have: number, need: number): number
		return if need > 0 then math.clamp(have / need, 0, 1) else 1
	end
	if room then
		if stars < room.StarsNeeded then
			return "Stars", ratio(stars, room.StarsNeeded)
		end
		return "Cash", ratio(cash, room.Price)
	end
	if upgrade then
		local level = (state.Upgrades and state.Upgrades[id]) or 0
		local price = upgrade.Prices[level + 1]
		return "Cash", if type(price) == "number" then ratio(cash, price) else 1
	end
	return "Stars", 1
end

function DayReportPanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "DayReport",
		Layer = "Popup",
		Title = "🌙 Day done!",
		Accent = ACCENT,
		MaxSize = Vector2.new(440, 470),
		Scale = Vector2.new(0.9, 0.92),
		Dim = false,
		AutoFocus = false,
	})
	-- One block of content, scaled down to fit a short landscape phone.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.fromScale(0.5, 0)
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = modal.Body
	local list = Kit.list(content, Enum.FillDirection.Vertical, 8)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(content, modal.Body)

	-- The big number: gold outlined display text on turning rays.
	local score = Instance.new("Frame")
	score.Name = "Score"
	score.BackgroundTransparency = 1
	score.LayoutOrder = 1
	score.Size = UDim2.new(1, 0, 0, 72)
	score.Parent = content
	local burst = Instance.new("Frame") -- a square in the middle, so the rays stay round and close
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(60, 60)
	burst.ZIndex = 1
	burst.Parent = score
	local rays = Kit.rays(burst, Theme.Colors.Cash)
	rays.Visible = false -- only while the card is up (a hidden ray burst doesn't turn)
	local cured = Kit.label({
		Name = "Cured",
		Text = "😊 0",
		TextScaled = true,
		Outlined = true,
		TextColor3 = Theme.Colors.Cash,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = score,
	})
	textLimit(cured, 72)
	Kit.outline(cured, Theme.Size.StrokeLarge)
	local scoreValue = Instance.new("NumberValue")
	scoreValue.Parent = cured
	scoreValue.Changed:Connect(function(v: number)
		cured.Text = "😊 " .. Hud.format(math.floor(v + 0.5))
	end)

	-- ⭐ and 📖 chips
	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.LayoutOrder = 2
	chips.Size = UDim2.new(1, 0, 0, 44)
	chips.Parent = content
	Kit.list(chips, Enum.FillDirection.Horizontal, 10)
	local function chip(name: string, order: number, color: Color3): TextLabel
		local label = Kit.label({
			Name = name,
			Text = "",
			TextScaled = true,
			Outlined = true,
			LayoutOrder = order,
			BackgroundColor3 = Kit.lighten(color, 0.08),
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(120, 44),
			Parent = chips,
		})
		Kit.corner(label, 22)
		Kit.stroke(label, Theme.Colors.Outline, Theme.Size.Stroke)
		Palette.candyGradient(label)
		Kit.pad(label, 6)
		return label
	end
	local starsChip = chip("Stars", 1, Theme.Colors.Star)
	local pagesChip = chip("Pages", 2, Theme.Colors.Purple)

	-- New faces
	local faces = Instance.new("Frame")
	faces.Name = "NewPages"
	faces.BackgroundTransparency = 1
	faces.LayoutOrder = 3
	faces.Size = UDim2.new(1, 0, 0, 64)
	faces.Parent = content
	Kit.list(faces, Enum.FillDirection.Horizontal, 6)

	-- Next goal
	local nextCard = Instance.new("Frame")
	nextCard.Name = "Next"
	nextCard.LayoutOrder = 4
	nextCard.BackgroundColor3 = Theme.Colors.Paper
	nextCard.BorderSizePixel = 0
	nextCard.Size = UDim2.new(1, 0, 0, 76)
	Kit.corner(nextCard, 16)
	Kit.stroke(nextCard, Theme.Colors.Outline, Theme.Size.Stroke)
	nextCard.Parent = content
	Kit.label({
		Name = "Aim",
		Text = "🎯",
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Parent = nextCard,
	})
	-- What's next, on a candy tile.
	local nextTile = Instance.new("Frame")
	nextTile.Name = "Tile"
	nextTile.AnchorPoint = Vector2.new(0, 0.5)
	nextTile.Position = UDim2.new(0, 52, 0.5, 0)
	nextTile.Size = UDim2.fromOffset(52, 52)
	nextTile.BackgroundColor3 = Kit.lighten(Theme.Colors.Cyan, 0.08)
	nextTile.BorderSizePixel = 0
	Kit.corner(nextTile, 12)
	Kit.stroke(nextTile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(nextTile)
	Kit.gloss(nextTile, 4)
	nextTile.Parent = nextCard
	local nextIcon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = nextTile,
	})
	local nextName = Kit.label({
		Name = "Name",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 112, 0.5, 2),
		Size = UDim2.new(1, -112 - 84, 0, 26),
		Parent = nextCard,
	})
	textLimit(nextName, 22)
	-- How close you are: ⭐ toward the room's stars first, then 💰 toward its price (design §5.4).
	local nextTrack = Instance.new("Frame")
	nextTrack.Name = "Progress"
	nextTrack.AnchorPoint = Vector2.new(0, 0)
	nextTrack.Position = UDim2.new(0, 140, 0.5, 8)
	nextTrack.Size = UDim2.new(1, -140 - 84, 0, 14)
	nextTrack.BackgroundColor3 = Theme.Colors.Paper
	nextTrack.BorderSizePixel = 0
	Kit.corner(nextTrack, 7)
	Kit.stroke(nextTrack, Theme.Colors.Outline, 2)
	nextTrack.Parent = nextCard
	local nextFill = Instance.new("Frame")
	nextFill.Name = "Fill"
	nextFill.Size = UDim2.fromScale(0, 1)
	nextFill.BackgroundColor3 = Theme.Colors.Star
	nextFill.BorderSizePixel = 0
	Kit.corner(nextFill, 7)
	Palette.candyGradient(nextFill)
	nextFill.Parent = nextTrack
	local nextMeter = Kit.label({
		Name = "Meter",
		Text = "⭐",
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 112, 0.5, 15),
		Size = UDim2.fromOffset(22, 22),
		Parent = nextCard,
	})
	local goButton = Kit.button({
		Name = "Go",
		Kind = "Good",
		Text = "🛒",
		TextSize = Theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(64, Theme.Size.ButtonHeight),
		Parent = nextCard,
	})
	Kit.shine(goButton) -- opens the in-game 💰 Shop on your next goal (nothing paid lives there)

	-- The auto-close bar along the bottom of the card
	local timerTrack = Instance.new("Frame")
	timerTrack.Name = "AutoClose"
	timerTrack.BackgroundColor3 = Theme.Colors.Quiet
	timerTrack.BorderSizePixel = 0
	timerTrack.AnchorPoint = Vector2.new(0.5, 1)
	timerTrack.Position = UDim2.new(0.5, 0, 1, 4)
	timerTrack.Size = UDim2.new(1, -8, 0, 6)
	Kit.corner(timerTrack, 3)
	timerTrack.Parent = modal.Panel
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.BackgroundColor3 = ACCENT
	timerFill.BorderSizePixel = 0
	timerFill.Size = UDim2.fromScale(1, 1)
	Kit.corner(timerFill, 3)
	timerFill.Parent = timerTrack

	local shopTab = "Upgrades"
	goButton.Activated:Connect(function()
		modal.close()
		ctx.fire("Open", "Shop", shopTab)
	end)

	local token = 0
	local function show(report: Types.DayReportInfo)
		token += 1
		local mine = token

		-- The count rolls up from 0.
		scoreValue.Value = 0
		cured.Text = "😊 0"
		starsChip.Text = "⭐ +" .. Hud.format(report.StarsGained)
		pagesChip.Text = "📖 +" .. #report.NewPages
		pagesChip.Visible = #report.NewPages > 0

		faces:ClearAllChildren()
		Kit.list(faces, Enum.FillDirection.Horizontal, 6)
		local faceFrames: { GuiObject } = {}
		for index, patientId in report.NewPages do
			if index > MAX_FACES then
				local more = Kit.label({
					Name = "More",
					Text = "+" .. (#report.NewPages - MAX_FACES),
					TextScaled = true,
					Outlined = true,
					LayoutOrder = index,
					Size = UDim2.fromOffset(48, 48),
					Parent = faces,
				})
				table.insert(faceFrames, more)
				break
			end
			local look = Hud.lookOf(patientId)
			if look then
				local holder = Instance.new("Frame")
				holder.Name = patientId
				holder.LayoutOrder = index
				holder.BackgroundColor3 = Kit.lighten(Theme.Colors.Good, 0.6)
				holder.BorderSizePixel = 0
				holder.Size = UDim2.fromOffset(60, 60)
				Kit.corner(holder, 30)
				Kit.stroke(holder, Theme.Colors.Outline, Theme.Size.Stroke)
				Palette.candyGradient(holder)
				local portrait = Hud.portrait(look)
				portrait.AnchorPoint = Vector2.new(0.5, 0.5)
				portrait.Position = UDim2.fromScale(0.5, 0.5)
				portrait.Size = UDim2.fromScale(0.9, 0.9)
				portrait.Parent = holder
				holder.Parent = faces
				table.insert(faceFrames, holder)
			end
		end
		faces.Visible = #report.NewPages > 0
		rays.Visible = true

		local nextGoal = report.Next
		local hasNext = nextGoal.Kind ~= "None" and nextGoal.Id ~= ""
		nextCard.Visible = hasNext
		if hasNext then
			local room = if nextGoal.Kind == "Room" then rawget(data.Rooms, nextGoal.Id) else nil
			local upgrade = if nextGoal.Kind == "Upgrade" then rawget(data.Upgrades, nextGoal.Id) else nil
			local thing = room or upgrade
			nextIcon.Text = if nextGoal.Icon ~= "" then nextGoal.Icon elseif thing then thing.Icon else "🎯"
			nextName.Text = if thing then thing.Name else ""
			shopTab = if room then "Rooms" else "Upgrades"
			local meter, ratio = progressTo(ctx.State, room, upgrade, nextGoal.Id)
			nextMeter.Text = if meter == "Stars" then "⭐" else "💰"
			nextFill.BackgroundColor3 = if meter == "Stars" then Theme.Colors.Star else Theme.Colors.Cash
			nextFill.Size = UDim2.fromScale(ratio, 1)
		end

		modal.open()
		-- New faces pop in one after another (Kit.bump does nothing with reduced motion).
		for index, face in faceFrames do
			task.delay(0.3 + index * FACE_STAGGER, function()
				if token == mine then
					Kit.bump(face)
				end
			end)
		end
		if Hud.calm() then
			scoreValue.Value = report.Cured
		else
			task.delay(0.25, function()
				if token == mine then
					TweenService:Create(
						scoreValue,
						TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Value = report.Cured }
					):Play()
					task.delay(0.9, function()
						if token == mine then
							Kit.bump(score) -- the number and its rays spring together
							Kit.bump(starsChip)
							if pagesChip.Visible then
								task.delay(FACE_STAGGER, Kit.bump, pagesChip)
							end
							Hud.sound("Fanfare")
							if report.StarsGained > 0 then
								Hud.fly(starsChip, "⭐", "Stars", math.min(report.StarsGained, 6))
							end
						end
					end)
				end
			end)
		end

		timerFill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(timerFill, TweenInfo.new(AUTO_CLOSE, Enum.EasingStyle.Linear), {
			Size = UDim2.fromScale(0, 1),
		}):Play()
		task.delay(AUTO_CLOSE, function()
			if token == mine then
				modal.close()
			end
		end)
	end

	ctx.on("ModalClosed", function(name: any)
		if name == "DayReport" then
			rays.Visible = false
		end
	end)

	ctx.Remotes.DayReport.OnClientEvent:Connect(function(raw: any)
		local report = clean(raw)
		if report and (report.Cured > 0 or #report.NewPages > 0 or report.StarsGained > 0) then
			show(report)
		end
	end)
end

return DayReportPanel
