--!strict
-- DayReportPanel (build plan Task 6): the end-of-day card, popped when the server sends DayReport (at night's
-- end). A big count of patients cured, ⭐ gained, the new Book pages as faces, and the one clear "next goal"
-- with a bar showing how close it is (⭐ toward its stars, then 💰 toward its price) and a 🛒 button that opens
-- the Shop on it. It closes by itself after AUTO_CLOSE seconds.
--   init(ctx)   listens to the DayReport remote
-- It doesn't dim the screen or grab gamepad focus: it arrives on its own while you play, so it never blocks you.
-- A day with nothing cured shows nothing (no "you did nothing" screen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local DayReportPanel = {}

local AUTO_CLOSE = 8
local MAX_FACES = 5

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

	-- The big number
	local cured = Kit.label({
		Name = "Cured",
		Text = "😊 0",
		TextScaled = true,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 72),
		Parent = content,
	})
	textLimit(cured, 72)
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
			LayoutOrder = order,
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(120, 44),
			Parent = chips,
		})
		Kit.corner(label, 22)
		Kit.stroke(label, Kit.shade(color, 0.3), 2.5)
		Kit.pad(label, 6)
		return label
	end
	local starsChip = chip("Stars", 1, Theme.Colors.Star)
	local pagesChip = chip("Pages", 2, Color3.fromRGB(198, 226, 255))

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
	nextCard.BackgroundColor3 = Theme.Colors.Card
	nextCard.BorderSizePixel = 0
	nextCard.Size = UDim2.new(1, 0, 0, 76)
	Kit.corner(nextCard, 16)
	local nextStroke = Kit.stroke(nextCard, Theme.Colors.Stroke, 2)
	nextStroke.Transparency = 0.5
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
	local nextIcon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 52, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		Parent = nextCard,
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
	nextTrack.BackgroundColor3 = Theme.Colors.Quiet
	nextTrack.BorderSizePixel = 0
	Kit.corner(nextTrack, 7)
	nextTrack.Parent = nextCard
	local nextFill = Instance.new("Frame")
	nextFill.Name = "Fill"
	nextFill.Size = UDim2.fromScale(0, 1)
	nextFill.BackgroundColor3 = Theme.Colors.Star
	nextFill.BorderSizePixel = 0
	Kit.corner(nextFill, 7)
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
		Kind = "Primary",
		Text = "🛒",
		TextSize = Theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(64, Theme.Size.ButtonHeight),
		Parent = nextCard,
	})

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
	timerFill.BackgroundColor3 = Theme.Colors.Secondary
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
		for index, patientId in report.NewPages do
			if index > MAX_FACES then
				Kit.label({
					Name = "More",
					Text = "+" .. (#report.NewPages - MAX_FACES),
					TextScaled = true,
					LayoutOrder = index,
					Size = UDim2.fromOffset(48, 48),
					Parent = faces,
				})
				break
			end
			local look = Hud.lookOf(patientId)
			if look then
				local holder = Instance.new("Frame")
				holder.Name = patientId
				holder.LayoutOrder = index
				holder.BackgroundColor3 = Theme.Colors.Card
				holder.BorderSizePixel = 0
				holder.Size = UDim2.fromOffset(60, 60)
				Kit.corner(holder, 30)
				Kit.stroke(holder, Theme.Colors.Good, 3)
				local portrait = Hud.portrait(look)
				portrait.AnchorPoint = Vector2.new(0.5, 0.5)
				portrait.Position = UDim2.fromScale(0.5, 0.5)
				portrait.Size = UDim2.fromScale(0.9, 0.9)
				portrait.Parent = holder
				holder.Parent = faces
			end
		end
		faces.Visible = #report.NewPages > 0

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
							Hud.pop(cured, 1.15)
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

	ctx.Remotes.DayReport.OnClientEvent:Connect(function(raw: any)
		local report = clean(raw)
		if report and (report.Cured > 0 or #report.NewPages > 0 or report.StarsGained > 0) then
			show(report)
		end
	end)
end

return DayReportPanel
