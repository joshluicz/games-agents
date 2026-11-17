--!strict
-- DayReportPanel (build plan Task 6): the end-of-day card, popped when the server sends DayReport (at night's
-- end). It starts with THREE lines (UI direction "What a Lv 1 player sees"; memory-20261117-006): the patients
-- treated (the big count), the cash earned (when the report carries it: CashGained) and the stars gained; the
-- rest joins as its feature unlocks: the new Book pages as faces (a day with new pages), and the one clear "next
-- goal" with a bar showing how close it is (stars toward its stars, then cash toward its price) and a "Shop"
-- button that opens the Shop on it (once the player has used the Shop: Pure.visible). It closes by itself after
-- AUTO_CLOSE seconds.
--   init(ctx)   listens to the DayReport remote
--   DayReportPanel.Pure   what shows and its words (tests/ProgressionPanels.spec loads the PURE block on its own)
-- It doesn't dim the screen or grab gamepad focus: it arrives on its own while you play, so it never blocks you.
-- A day with nobody treated shows nothing (no "you did nothing" screen), and neither does a day that ends while
-- you're in the first-session tutorial (the server doesn't send one then either: Server/DayReport).
-- Look (UI/Modal's navy header on a no-dim popup, the title in words; the calm UI, docs/plan/2026-11-17-ui-
-- direction.md §4 #10; Joshua, memory-20261117-007): the count is the reward moment: big gold outlined display text
-- at Theme.TextSize.Hero on turning rays (the number alone: an emoji can't be outlined), "patients treated" under
-- it, then the cash and stars as Kit.unit rows (the Unit apart from its number); new faces on round Well tiles; the
-- next goal on a Kit.card with its Art, a Kit.bar (navy) and ONE Primary "Shop" (it opens the in-game Shop: it
-- never shines or breathes, nothing loud points at spending).
-- Juice (depth update, design §4): the count rolls up from 0 with a tick per number (Kit.countUp), then lands with
-- a fanfare and a confetti burst from it; the stars roll their "+n" and fly into the HUD's stars; the faces come
-- together (a list never pops one by one); the next goal's bar fills up. Calm: the numbers are just there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local DayReportPanel = {}

------------------------------------------------------------------------------------------------------------------
-- Pure: the report's shape, what shows, its words. No Roblox; only UI/Icons (a pure library).
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

export type Report = {
	Cured: number,
	CashGained: number?, -- Server/DayReport sends it (the day's treatment cash); a report without it has no Cash line
	NewPages: { string },
	StarsGained: number,
	Next: { Kind: string, Id: string, Icon: string },
}

Pure.TEXT = {
	Title = "Day done!",
	Treated = "patients treated",
	Shop = "Shop",
	StarsMeter = "Stars to unlock",
	CashMeter = "Cash to buy",
}

local function count(value: any): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
		then math.max(0, math.floor(value))
		else 0
end

-- The report comes from the server, but check its shape anyway so a bad one can't break the UI.
function Pure.clean(report: any): Report?
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
		Cured = count(report.Cured),
		CashGained = if type(report.CashGained) == "number" then count(report.CashGained) else nil,
		NewPages = pages,
		StarsGained = count(report.StarsGained),
		Next = {
			Kind = if type(nextGoal.Kind) == "string" then nextGoal.Kind else "None",
			Id = if type(nextGoal.Id) == "string" then nextGoal.Id else "",
			Icon = if type(nextGoal.Icon) == "string" then nextGoal.Icon else "",
		},
	}
end

-- The player has used the Shop: a level bought, an upgrade, or a room past the Stand.
function Pure.shopUsed(state: any): boolean
	if type(state) ~= "table" then
		return false
	end
	if type(state.Level) == "number" and state.Level >= 2 then
		return true
	end
	if type(state.Upgrades) == "table" then
		for _, level in state.Upgrades do
			if type(level) == "number" and level > 0 then
				return true
			end
		end
	end
	if type(state.Rooms) == "table" then
		for id, owned in state.Rooms do
			if owned == true and id ~= "Stand" then
				return true
			end
		end
	end
	return false
end

-- R0: what the card shows. The three lines (treated, cash when sent, stars) always; the pages on a day with new
-- pages; the next goal once there is one and the player has used the Shop.
function Pure.visible(report: Report, state: any): { [string]: boolean }
	local hasNext = report.Next.Kind ~= "None" and report.Next.Id ~= ""
	return {
		Cured = true,
		Cash = report.CashGained ~= nil,
		Stars = true,
		Pages = #report.NewPages > 0,
		Next = hasNext and Pure.shopUsed(state),
	}
end

-- "+2 new pages" (words: the faces beside it are the art).
function Pure.pagesText(n: number): string
	return "+" .. n .. (if n == 1 then " new page" else " new pages")
end

-- What the next goal's bar measures, in words.
function Pure.meterText(meter: string): string
	return if meter == "Stars" then Pure.TEXT.StarsMeter else Pure.TEXT.CashMeter
end
-- PURE-END

DayReportPanel.Pure = Pure

local AUTO_CLOSE = 8
local MAX_FACES = 5
local COUNT_SECONDS = 0.9 -- the big count's roll
local UNIT_PX = Theme.TextSize.Title

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
		Title = Pure.TEXT.Title,
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
	local list = Kit.list(content, Enum.FillDirection.Vertical, Theme.Space.Line)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(content, modal.Body)

	-- Line 1, the big number: gold outlined display text on turning rays, "patients treated" under it.
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
		Text = "0",
		TextScaled = true,
		Outlined = true,
		Font = Theme.DisplayFont,
		TextColor3 = Theme.Colors.Cash,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = score,
	})
	Kit.textLimit(cured, Theme.TextSize.Hero)
	Kit.outline(cured, Theme.Stroke.Panel)
	local function curedText(n: number): string
		return Hud.format(math.floor(n + 0.5))
	end
	Kit.fact({
		Name = "Treated",
		Text = Pure.TEXT.Treated,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = content,
	})

	-- Lines 2 and 3: the cash and the stars, each a Unit glued to its number (two labels: Kit.unit).
	local units = Instance.new("Frame")
	units.Name = "Units"
	units.BackgroundTransparency = 1
	units.LayoutOrder = 3
	units.Size = UDim2.new(1, 0, 0, UNIT_PX + Theme.Space.Line)
	units.Parent = content
	local unitList = Kit.list(units, Enum.FillDirection.Horizontal, Theme.Space.Section)
	unitList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local cashRow, cashAmount = Kit.unit({
		Name = "Cash",
		Icon = Icons.Unit.Cash,
		Text = "+0",
		Px = UNIT_PX,
		LayoutOrder = 1,
		Parent = units,
	})
	local starsRow, starsAmount = Kit.unit({
		Name = "Stars",
		Icon = Icons.Unit.Stars,
		Text = "+0",
		Px = UNIT_PX,
		LayoutOrder = 2,
		Parent = units,
	})
	local function plusText(n: number): string
		return "+" .. Hud.format(math.floor(n + 0.5))
	end

	-- New faces (a day with new Book pages): the faces, and the count in words.
	local pagesLine = Kit.fact({
		Name = "Pages",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = content,
	})
	local faces = Instance.new("Frame")
	faces.Name = "NewPages"
	faces.BackgroundTransparency = 1
	faces.LayoutOrder = 5
	faces.Size = UDim2.new(1, 0, 0, 64)
	faces.Parent = content
	local function faceList()
		local row = Kit.list(faces, Enum.FillDirection.Horizontal, Theme.Space.Line)
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	faceList()

	-- Next goal, on a Kit.card: its Art, its name, what the bar measures, the bar, and the one Primary.
	local pad = Theme.Space.PadCard
	local nextCard = Kit.card({ Name = "Next", LayoutOrder = 6, Pad = false, Parent = content })
	nextCard.AutomaticSize = Enum.AutomaticSize.None
	nextCard.Size = UDim2.new(1, 0, 0, 80)
	local nextTile = Kit.artTile({
		Icon = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, pad, 0.5, 0),
		Parent = nextCard,
	})
	local nextIcon = nextTile:FindFirstChild("Icon") :: TextLabel
	local left = pad * 2 + Theme.Calm.ArtTile
	local goWidth = 96
	local right = goWidth + pad * 2
	local nextName = Kit.name({
		Name = "Name",
		Text = "",
		Position = UDim2.fromOffset(left, pad - Theme.Space.Tight),
		Size = UDim2.new(1, -left - right, 0, Theme.TextSize.Body + Theme.Space.Tight),
		Parent = nextCard,
	})
	-- How close you are: stars toward the room's stars first, then cash toward its price (design §5.4).
	local nextMeter = Kit.fact({
		Name = "Meter",
		Text = "",
		Position = UDim2.fromOffset(left, pad + 22),
		Size = UDim2.new(1, -left - right, 0, Theme.TextSize.Caption + Theme.Space.Tight),
		Parent = nextCard,
	})
	local _, setNextBar = Kit.bar({
		Name = "Progress",
		Position = UDim2.fromOffset(left, pad + 48),
		Size = UDim2.new(1, -left - right, 0, Theme.Calm.Bar),
		Parent = nextCard,
	})
	-- The view's ONE Primary: it opens the in-game Shop on your next goal (nothing paid lives there). It never
	-- shines or breathes.
	local goButton = Kit.button({
		Name = "Go",
		Kind = "Primary",
		Text = Pure.TEXT.Shop,
		TextSize = Theme.TextSize.Button,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -pad, 0.5, 0),
		Size = UDim2.fromOffset(goWidth, Theme.Size.ButtonHeight),
		Parent = nextCard,
	})

	-- The auto-close bar along the bottom of the card (a calm grey line, never red; nothing to buy here)
	local timerTrack = Instance.new("Frame")
	timerTrack.Name = "AutoClose"
	timerTrack.BackgroundColor3 = Theme.Colors.Well
	timerTrack.BorderSizePixel = 0
	timerTrack.AnchorPoint = Vector2.new(0.5, 1)
	timerTrack.Position = UDim2.new(0.5, 0, 1, Theme.Space.Tight)
	timerTrack.Size = UDim2.new(1, -Theme.Space.Line, 0, 6)
	Kit.corner(timerTrack, Theme.Radius.Small)
	timerTrack.Parent = modal.Panel
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.BackgroundColor3 = Theme.Colors.InkSoft
	timerFill.BorderSizePixel = 0
	timerFill.Size = UDim2.fromScale(1, 1)
	Kit.corner(timerFill, Theme.Radius.Small)
	timerFill.Parent = timerTrack

	local shopTab = "Upgrades"
	goButton.Activated:Connect(function()
		modal.close()
		ctx.fire("Open", "Shop", shopTab)
	end)

	local token = 0
	local function show(report: Report)
		token += 1
		local mine = token
		local shown = Pure.visible(report, ctx.State)

		-- The counts roll up from 0.
		Kit.countUp(cured, 0, curedText, 0)
		Kit.countUp(starsAmount, 0, plusText, 0)
		Kit.countUp(cashAmount, 0, plusText, 0)
		cashRow.Visible = shown.Cash
		starsRow.Visible = shown.Stars

		pagesLine.Visible = shown.Pages
		pagesLine.Text = Pure.pagesText(#report.NewPages)
		faces:ClearAllChildren()
		faceList()
		for index, patientId in report.NewPages do
			if index > MAX_FACES then
				Kit.fact({
					Name = "More",
					Text = "+" .. (#report.NewPages - MAX_FACES),
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
				holder.BackgroundColor3 = Theme.Colors.Well
				holder.BorderSizePixel = 0
				holder.Size = UDim2.fromOffset(60, 60)
				Kit.corner(holder, Theme.Radius.Round)
				local portrait = Hud.portrait(look)
				portrait.AnchorPoint = Vector2.new(0.5, 0.5)
				portrait.Position = UDim2.fromScale(0.5, 0.5)
				portrait.Size = UDim2.fromScale(0.9, 0.9)
				portrait.Parent = holder
				holder.Parent = faces
			end
		end
		faces.Visible = shown.Pages
		rays.Visible = true

		local nextGoal = report.Next
		nextCard.Visible = shown.Next
		local ratio = 0
		if shown.Next then
			local room = if nextGoal.Kind == "Room" then rawget(data.Rooms, nextGoal.Id) else nil
			local upgrade = if nextGoal.Kind == "Upgrade" then rawget(data.Upgrades, nextGoal.Id) else nil
			local thing = room or upgrade
			nextIcon.Text = if nextGoal.Icon ~= "" then nextGoal.Icon elseif thing then thing.Icon else ""
			nextName.Text = if thing then thing.Name else ""
			shopTab = if room then "Rooms" else "Upgrades"
			local meter
			meter, ratio = progressTo(ctx.State, room, upgrade, nextGoal.Id)
			nextMeter.Text = Pure.meterText(meter)
			setNextBar(if Hud.calm() then ratio else 0) -- fills up once the count has landed
			if not Hud.calm() then
				task.delay(1.3, function()
					if token == mine then
						setNextBar(ratio)
					end
				end)
			end
		end

		modal.open()
		-- The new faces come together, once (a list never pops one by one; Kit.bump does nothing with calm).
		if shown.Pages then
			task.delay(0.3, function()
				if token == mine then
					Kit.bump(faces)
				end
			end)
		end
		if Hud.calm() then
			Kit.countUp(cured, report.Cured, curedText, 0)
			Kit.countUp(starsAmount, report.StarsGained, plusText, 0)
			Kit.countUp(cashAmount, report.CashGained or 0, plusText, 0)
		else
			task.delay(0.25, function()
				if token == mine then
					Kit.countUp(cured, report.Cured, curedText, COUNT_SECONDS)
					task.delay(COUNT_SECONDS, function()
						if token == mine then
							Kit.bump(score) -- the number and its rays spring together
							Kit.confetti(modal.Root, 26, UDim2.fromScale(0.5, 0.25))
							Kit.countUp(starsAmount, report.StarsGained, plusText, 0.5)
							Kit.countUp(cashAmount, report.CashGained or 0, plusText, 0.5)
							Hud.sound("Fanfare")
							if report.StarsGained > 0 then
								task.delay(
									0.5,
									Hud.fly,
									starsRow,
									Icons.Unit.Stars,
									"Stars",
									math.min(report.StarsGained, 6)
								)
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
		if TutorialLogic.active(ctx.State.Tutorial) then
			return -- the first-session tutorial stays quiet
		end
		local report = Pure.clean(raw)
		if report and (report.Cured > 0 or #report.NewPages > 0 or report.StarsGained > 0) then
			show(report)
		end
	end)
end

return DayReportPanel
