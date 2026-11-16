--!strict
-- Big celebration screens (depth-update design §4, build plan §B9). OWNER: T6.
--   init(ctx)   listens for the bus "Celebrate" (info: Types.CelebrateInfo): from the server for a level-up
--               ("LevelUp"), a first-time hire ("NewNurse") and a completed Journal group ("JournalSet"); Feel/CureFX
--               fires "Room" for a room you just got (with an extra field `Room = <RoomId>`, see Words.of)
-- What it shows: the screen dims, candy confetti rains, and in the middle the reward sits in a big white bubble on
-- turning rays (Kit.celebrate) under a big outlined title on a ribbon in the moment's colour: the new level's name
-- and its unlock chips (Data/Levels), the nurse's face with its rarity frame shimmering (Kit.rarityFrame) and its
-- rarity and role chips, a Journal group's 💰 and decor reward, or the room's name. A "🎉 Yay!" button breathes
-- (Kit.breathing) and closes it; so does a tap anywhere after a moment, ButtonB, or Theme.Juice.CelebrateSeconds
-- passing (no countdown: it just gets out of the way). On closing, a Journal group's cash flies into 💰 and a new
-- nurse's icon into the 👩‍⚕️ button. One at a time (a short queue), never while the first-session tutorial runs
-- (it waits for the tutorial to end). Calm (Kit.reducedMotion()): the rays hold still, no confetti, no bounce.
-- Sounds (Feel/Sounds over the bus): LevelUp, Celebrate (nurses and Journal sets), Fanfare (rooms).
-- Display only: the server already granted whatever this shows.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

------------------------------------------------------------------------------------------------------------------
-- Words: what a celebration says, from its info and the Data tables. Pure (no Roblox APIs): a scratch Lune harness
-- loads the block between the markers on its own, so keep it self-contained.
------------------------------------------------------------------------------------------------------------------
-- BEGIN PURE
local Words = {}

export type CelebrateWords = {
	Kind: string,
	Title: string, -- ≤ 3 words
	Icon: string,
	Sub: string, -- one line under the title ("" = none)
	Chips: { string }, -- up to 4 small chips (an emoji and a word or two)
	Rarity: string?, -- a nurse's or a Journal group's rarity (its colour and frame)
	NurseId: string?, -- a nurse to draw
	Cash: number?, -- a Journal group's cash (flies into 💰 on closing)
	Sound: string, -- the Feel/Sounds cue
}

local KINDS = { LevelUp = "LevelUp", NewNurse = "Celebrate", JournalSet = "Celebrate", Room = "Fanfare" }
-- The same role icons as the belt and the Journal (UI/BeltView Pure.ROLE_ICONS; tests/Juice checks they match). Never
-- an item's icon (🧪 Potion, 🩹 Plaster): a pre-reader would read a Healer as a plaster.
local ROLE_ICONS = { Maker = "🛠️", Healer = "🩺", Cheerer = "🎉" }
Words.ROLE_ICONS = ROLE_ICONS
local MAX_CHIPS = 4
local MAX_TITLE_WORDS = 3

function Words.commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

local function cutWords(text: string, max: number): string
	local words = {}
	for word in string.gmatch(text, "%S+") do
		if #words >= max then
			break
		end
		table.insert(words, word)
	end
	return table.concat(words, " ")
end

-- A row of a keyed Data map by id (rawget, so a map's .Order is never an id).
local function entry(map: any, id: any): any
	if type(map) ~= "table" or type(id) ~= "string" or id == "" then
		return nil
	end
	local found = rawget(map, id)
	return if type(found) == "table" then found else nil
end

-- What to show for a CelebrateInfo; nil for junk (no table, an unknown Kind, no Title or Icon).
-- data = { Nurses, Rarities, Levels, Decor, Rooms } (ctx.Data).
function Words.of(info: any, data: any): CelebrateWords?
	if type(info) ~= "table" or type(info.Kind) ~= "string" or KINDS[info.Kind] == nil then
		return nil
	end
	if type(info.Title) ~= "string" or info.Title == "" or type(info.Icon) ~= "string" then
		return nil
	end
	local words: CelebrateWords = {
		Kind = info.Kind,
		Title = cutWords(info.Title, MAX_TITLE_WORDS),
		Icon = info.Icon,
		Sub = "",
		Chips = {},
		Rarity = nil,
		NurseId = nil,
		Cash = nil,
		Sound = KINDS[info.Kind],
	}
	local function chip(text: string?)
		if text and text ~= "" and #words.Chips < MAX_CHIPS then
			table.insert(words.Chips, text)
		end
	end
	local function rarityOf(id: any): string?
		return if entry(data.Rarities, id) then id else nil
	end

	if info.Kind == "LevelUp" then
		local level = info.Level
		local levels = data.Levels
		local row = if type(level) == "number"
				and level == math.floor(level)
				and type(levels) == "table"
			then levels[level]
			else nil
		if type(row) == "table" then
			words.Sub = "Lv " .. level .. " · " .. tostring(row.Name)
			if type(row.Unlocks) == "table" then
				for _, unlock in row.Unlocks do
					chip(if type(unlock) == "string" then unlock else nil)
				end
			end
		end
	elseif info.Kind == "NewNurse" then
		local nurse = entry(data.Nurses, info.NurseId)
		if nurse then
			words.NurseId = info.NurseId
			words.Rarity = rarityOf(nurse.Rarity)
			words.Sub = tostring(nurse.Name)
			local rarity = entry(data.Rarities, nurse.Rarity)
			if rarity then
				chip(rarity.Icon .. " " .. nurse.Rarity)
			end
			local roleIcon = ROLE_ICONS[nurse.Role]
			if roleIcon then
				chip(roleIcon .. " " .. nurse.Role)
			end
		else
			words.Rarity = rarityOf(info.Rarity)
		end
		if type(info.Level) == "number" and info.Level > 1 then
			chip("⬆️ Lv " .. math.floor(info.Level))
		end
	elseif info.Kind == "JournalSet" then
		words.Rarity = rarityOf(info.Rarity)
		local rarity = entry(data.Rarities, info.Rarity)
		if rarity then
			words.Sub = rarity.Icon .. " " .. info.Rarity .. " nurses"
		end
		if type(info.Cash) == "number" and info.Cash > 0 then
			words.Cash = math.floor(info.Cash)
			chip("💰 " .. Words.commas(info.Cash))
		end
		local decor = entry(data.Decor, info.Decor)
		if decor then
			chip(tostring(decor.Icon) .. " " .. tostring(decor.Name))
		end
	elseif info.Kind == "Room" then
		local room = entry(data.Rooms, info.Room)
		if room then
			words.Sub = tostring(room.Name)
		end
	end
	return words
end
-- END PURE

local Celebrate = {}
Celebrate.Words = Words

local MAX_QUEUE = 4
local TAP_GUARD = 0.7 -- seconds before a tap on the dim closes it (so the tap that caused it can't)
local BUBBLE = 150
local DIM = 0.35
local CLOSE_ACTION = "ClinicCloseCelebrate"

local ACCENTS: { [string]: Color3 } = {
	LevelUp = Theme.Colors.Primary,
	NewNurse = Theme.Colors.Cyan,
	JournalSet = Theme.Colors.Purple,
	Room = Theme.Colors.Good,
}

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 14
	limit.Parent = label
end

function Celebrate.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local gui = Kit.screen("Celebrate", Theme.DisplayOrder.Celebrate)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.BackgroundColor3 = Theme.Colors.Shade
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Position = UDim2.fromOffset(-400, -400)
	dim.Size = UDim2.new(1, 800, 1, 800)
	dim.Parent = gui

	-- Confetti rains across the whole screen (above the dim, below the card).
	local rain = Instance.new("Frame")
	rain.Name = "Rain"
	rain.BackgroundTransparency = 1
	rain.Size = UDim2.fromScale(1, 1)
	rain.Parent = gui

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(0.94, 0.94)
	stage.BackgroundTransparency = 1
	stage.Visible = false
	local stageLimit = Instance.new("UISizeConstraint")
	stageLimit.MaxSize = Vector2.new(520, 580)
	stageLimit.Parent = stage
	stage.Parent = gui

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.fromScale(0.5, 0)
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = stage
	local list = Kit.list(content, Enum.FillDirection.Vertical, 10)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(content, stage)

	-- The reward: a white bubble (with an outer ring for a rarity frame) on rays and confetti.
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.LayoutOrder = 1
	burst.Size = UDim2.new(1, 0, 0, BUBBLE + 70)
	burst.Parent = content
	local core = Instance.new("Frame") -- a square in the middle, so the rays stay round
	core.Name = "Core"
	core.BackgroundTransparency = 1
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromOffset(BUBBLE + 40, BUBBLE + 40)
	core.ZIndex = 1
	core.Parent = burst
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(BUBBLE + 12, BUBBLE + 12)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	Kit.corner(ring, (BUBBLE + 12) // 2)
	ring.Parent = core
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
	bubble.BackgroundColor3 = Theme.Colors.Paper
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	Kit.corner(bubble, BUBBLE // 2)
	Kit.stroke(bubble, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(bubble)
	bubble.Parent = core
	local face = Instance.new("Frame") -- the icon or the nurse's portrait
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.82, 0.82)
	face.BackgroundTransparency = 1
	face.ZIndex = 3
	face.Parent = bubble
	local sticker = Kit.label({ -- the rarity's icon on the bubble's corner, or "NEW!"
		Name = "Sticker",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Dot,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.12),
		Size = UDim2.fromOffset(74, 34),
		Rotation = 10,
		Visible = false,
		ZIndex = 4,
		Parent = bubble,
	})
	Kit.corner(sticker, 17)
	Kit.stroke(sticker, Theme.Colors.Outline, 2.5)
	Kit.pad(sticker, 4)

	-- The title on a candy ribbon.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.LayoutOrder = 2
	ribbon.Size = UDim2.new(0.92, 0, 0, 72)
	ribbon.BorderSizePixel = 0
	Kit.corner(ribbon, Theme.Size.CornerLarge)
	Kit.stroke(ribbon, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(ribbon)
	Kit.gloss(ribbon, 14)
	ribbon.Parent = content
	local title = Kit.label({
		Name = "Title",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 56),
		ZIndex = 2,
		Parent = ribbon,
	})
	textLimit(title, 56)
	Kit.outline(title, Theme.Size.StrokeLarge)

	local sub = Kit.label({
		Name = "Sub",
		Text = "",
		Outlined = true,
		Font = Theme.Font,
		TextScaled = true,
		TextWrapped = false,
		LayoutOrder = 3,
		Size = UDim2.new(0.92, 0, 0, 36),
		Parent = content,
	})
	textLimit(sub, 30)
	Kit.outline(sub, Theme.Size.Stroke)

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.LayoutOrder = 4
	chips.Size = UDim2.fromScale(0.96, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.Parent = content
	local chipList = Kit.list(chips, Enum.FillDirection.Horizontal, 8)
	chipList.Wraps = true
	chipList.VerticalAlignment = Enum.VerticalAlignment.Top
	local chipPad = Instance.new("UIPadding") -- room for the chips' outlines
	chipPad.PaddingTop = UDim.new(0, 3)
	chipPad.PaddingBottom = UDim.new(0, 3)
	chipPad.Parent = chips

	local yay = Kit.button({
		Name = "Yay",
		Kind = "Good",
		Text = "🎉 Yay!",
		TextSize = Theme.TextSize.Title,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(220, 64),
		Parent = content,
	})
	Kit.shine(yay)
	Kit.breathing(yay)

	--------------------------------------------------------------------------------------------------------------
	-- Showing one
	--------------------------------------------------------------------------------------------------------------
	local queue: { CelebrateWords } = {}
	local showing = false
	local current: CelebrateWords? = nil
	local token = 0
	local openedAt = 0
	local stopFx: { () -> () } = {}
	local closeNow: () -> () = function() end

	local function clearFx()
		for _, stop in stopFx do
			stop()
		end
		table.clear(stopFx)
	end

	local function makeChip(text: string, order: number): TextLabel
		local label = Kit.label({
			Name = "Chip",
			Text = text,
			TextScaled = true,
			TextWrapped = false,
			LayoutOrder = order,
			BackgroundColor3 = Theme.Colors.Paper,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(190, 40),
			Parent = chips,
		})
		textLimit(label, 22)
		Kit.corner(label, 20)
		Kit.stroke(label, Theme.Colors.Outline, Theme.Size.Stroke)
		local pad = Kit.pad(label, 6)
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		return label
	end

	local function draw(words: CelebrateWords)
		local accent = if words.Rarity
			then Kit.rarityColor(words.Rarity)
			else ACCENTS[words.Kind] or Theme.Colors.Primary
		ribbon.BackgroundColor3 = Kit.lighten(accent, 0.08)
		title.Text = words.Icon .. " " .. words.Title
		sub.Text = words.Sub
		sub.Visible = words.Sub ~= ""

		face:ClearAllChildren()
		local nurse = if words.NurseId then rawget(data.Nurses, words.NurseId) else nil
		if nurse then
			local portrait = Hud.portrait(nurse.Look)
			portrait.ZIndex = 3
			portrait.Parent = face
		else
			Kit.label({
				Name = "Icon",
				Text = words.Icon,
				TextScaled = true,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = face,
			})
		end
		bubble.BackgroundColor3 = if nurse then Kit.lighten(accent, 0.55) else Theme.Colors.Paper

		local frame = ring:FindFirstChild("RarityFrame")
		if frame then
			frame:Destroy()
		end
		if words.Rarity then
			table.insert(stopFx, Kit.rarityFrame(ring, words.Rarity))
		end
		if words.Kind == "NewNurse" then
			sticker.Text = "NEW!"
			sticker.BackgroundColor3 = Theme.Colors.Dot
			sticker.Visible = true
		elseif words.Rarity then
			local rarity = rawget(data.Rarities, words.Rarity)
			sticker.Text = if rarity then rarity.Icon else ""
			sticker.BackgroundColor3 = Kit.lighten(accent, 0.08)
			sticker.Visible = rarity ~= nil
		else
			sticker.Visible = false
		end

		for _, child in chips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, text in words.Chips do
			makeChip(text, index)
		end
		chips.Visible = #words.Chips > 0
	end

	-- Things the reward leaves behind as it closes: cash into 💰, a new nurse into 👩‍⚕️.
	local function afterClose(words: CelebrateWords)
		if words.Cash and words.Cash > 0 then
			Hud.fly(nil, "💰", "Cash", Kit.Juice.coins(words.Cash))
		end
		if words.NurseId then
			local nurse = rawget(data.Nurses, words.NurseId)
			Hud.fly(nil, if nurse then nurse.Icon else "👩‍⚕️", "Nurses", 1)
		end
	end

	local function bindClose(on: boolean)
		if not on then
			ContextActionService:UnbindAction(CLOSE_ACTION)
			return
		end
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState: Enum.UserInputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			closeNow()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonB)
	end

	local function show(words: CelebrateWords)
		token += 1
		local mine = token
		current = words
		openedAt = os.clock()
		local calm = Kit.reducedMotion()
		clearFx() -- anything the last one left (its close animation was cut short)
		draw(words)

		gui.Enabled = true
		if calm then
			dim.BackgroundTransparency = DIM
		else
			dim.BackgroundTransparency = 1
			TweenService:Create(dim, Theme.Tween.Fade, { BackgroundTransparency = DIM }):Play()
		end
		Kit.popIn(stage)
		table.insert(stopFx, Kit.celebrate(core, Kit.lighten(ACCENTS[words.Kind] or Theme.Colors.Cash, 0.2)))
		Kit.confetti(rain, Theme.Juice.ConfettiPieces + 12)
		Hud.sound(words.Sound)

		-- The reward springs in, then the title, then each chip.
		if not calm then
			Kit.punch(bubble, 0.3, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
			bubble.Rotation = -14
			TweenService:Create(bubble, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Rotation = 0,
			}):Play()
			task.delay(0.18, function()
				if token == mine then
					Kit.punch(ribbon, 1.25, Theme.Tween.Bump)
				end
			end)
			local index = 0
			for _, child in chips:GetChildren() do
				if child:IsA("GuiObject") then
					index += 1
					task.delay(0.35 + index * 0.09, function()
						if token == mine and child.Parent then
							Kit.bump(child)
							Hud.sound("Pop", 0.5)
						end
					end)
				end
			end
		else
			bubble.Rotation = 0
		end

		bindClose(true)
		if usesDirectionalFocus() then
			GuiService.SelectedObject = yay
		end
		task.delay(Theme.Juice.CelebrateSeconds, function()
			if token == mine then
				closeNow()
			end
		end)
	end

	local function nextOne()
		if showing then
			return
		end
		showing = true
		task.spawn(function()
			while #queue > 0 do
				-- The first-session tutorial stays quiet: wait for it to end.
				while TutorialLogic.active(ctx.State.Tutorial) do
					task.wait(1)
				end
				local words = table.remove(queue, 1) :: CelebrateWords
				local ok, err = pcall(show, words)
				if not ok then
					warn("[Celebrate] show failed:", err)
					current = nil
				end
				while current do
					task.wait(0.1)
				end
				task.wait(0.25)
			end
			showing = false
		end)
	end

	closeNow = function()
		local words = current
		if not words then
			return
		end
		current = nil
		token += 1
		bindClose(false)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		Hud.sound("Close")
		local function finish()
			if current == nil then -- not already showing the next one
				clearFx()
				gui.Enabled = false
			end
		end
		if Kit.reducedMotion() then
			finish()
		else
			TweenService:Create(dim, Theme.Tween.Fade, { BackgroundTransparency = 1 }):Play()
			Kit.popOut(stage, finish)
		end
		afterClose(words)
	end

	yay.Activated:Connect(function()
		closeNow()
	end)
	dim.Activated:Connect(function()
		if os.clock() - openedAt >= TAP_GUARD then
			closeNow()
		end
	end)

	ctx.on("Celebrate", function(info: any)
		local words = Words.of(info, data)
		if not words or #queue >= MAX_QUEUE then
			return
		end
		table.insert(queue, words)
		nextOne()
	end)
end

return Celebrate
