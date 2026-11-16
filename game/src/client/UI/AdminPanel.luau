--!strict
-- AdminPanel (game/README.md "Admin panel"): the 🛠️ Admin panel for the two developer accounts, to test progression
-- quickly in the live game and in Studio.
--   init(ctx)   opens on ctx.fire("Open", "Admin"): the 🛠️ button in the HUD's ⚙️ panel sends it, and that button
--               only shows while the server has set the player attribute IsAdmin (Server/Admin)
-- The panel is just buttons. Each one asks the Admin remote (action, arg?); the server checks again that you're an
-- admin, validates the action and its argument (Logic/Admin) and answers (ok, message), shown as a toast. Nothing
-- here is trusted, and nothing on screen changes until the server's next Snapshot.
--
-- Four pages, THE tab column down the left (Modal.tabs; the look overhaul's template, look build plan §B8):
--   🛠️ Tools      your own save (💰 ⭐ rooms, decor, the Book, stories, goals and mail, play time, badges and boosts,
--                 the tutorial), then the whole server's night, day and winter (the server allows those only when
--                 you're alone in it, or in Studio; otherwise its reply says why)
--   🏢 Branch     Progression v2 (build plan §B8): 🏢 Rebirth now, 🌳 +3 points, ⬆️ Nurse levels, ✨ Charge
--                 abilities, 🚑 Ambulance, 🚁 Helicopter, and the whole server's 🏢 Restock Agency
--   🤧 Patients   tap a creature and it's next in your own line
--   🎁 Nurses     tap a nurse and it's yours, free (the roster rules still apply)
-- Buttons by role: every tool is Secondary; the ones that reset something (🔄 Restart the tutorial, 🏢 Rebirth now,
-- 🎯 Reset goals) are Destructive and ask Hud.confirm first ("Not now" focused).
-- Phones: every page scrolls and every button is at least 56 px tall, no text under 18 px. Motion is Kit's and Hud's,
-- so it honours reduced motion and the ✨ calm switch.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local AdminPanel = {}

local NAME = "Admin" -- the modal, and the "Open" bus name
local ATTRIBUTE = "IsAdmin" -- set by Server/Admin; only steers the UI
local ROW = Theme.Size.ButtonHeight
local CARD_ROW = 68
local GAP = Theme.Space.Gap

-- One button: an Admin remote call (Action, Arg). Kind is its role: "Secondary", or "Destructive" for a reset (it
-- asks Hud.confirm first, with Confirm as the question's line).
type Act = { Text: string, Kind: string, Action: string, Arg: (number | string)?, Confirm: string? }
type Section = { Title: string, Rows: { { Act } } }

local PAGES = {
	{ Id = "Actions", Icon = "🛠️", Caption = "Tools" },
	{ Id = "Branch", Icon = "🏢", Caption = "Branch" },
	{ Id = "Patients", Icon = "🤧", Caption = "Patients" },
	{ Id = "Nurses", Icon = "🎁", Caption = "Nurses" },
}

local SECTIONS: { Section } = {
	{
		Title = "👤 Your save",
		Rows = {
			{
				{ Text = "+1,000 💰", Kind = "Secondary", Action = "AddCash", Arg = 1000 },
				{ Text = "+10,000 💰", Kind = "Secondary", Action = "AddCash", Arg = 10000 },
			},
			{
				{ Text = "+10 ⭐", Kind = "Secondary", Action = "AddStars", Arg = 10 },
				{ Text = "+100 ⭐", Kind = "Secondary", Action = "AddStars", Arg = 100 },
			},
			{
				{ Text = "🏠 All rooms", Kind = "Secondary", Action = "UnlockRooms" },
				{ Text = "🌸 All decor", Kind = "Secondary", Action = "AllDecor" },
			},
			{
				{ Text = "📖 Full Book", Kind = "Secondary", Action = "CompleteBook" },
				{ Text = "💌 Stories today", Kind = "Secondary", Action = "StoriesDue" },
			},
			{
				{
					Text = "🎯 Reset goals + 📬",
					Kind = "Destructive",
					Action = "ResetDaily",
					Confirm = "New goals and mail",
				},
			},
		},
	},
	{
		Title = "⏱️ Play time · badges · boosts",
		Rows = {
			{
				{ Text = "🎁 +10 min today", Kind = "Secondary", Action = "AddPlayToday" },
				{ Text = "⏱️ +5 h total", Kind = "Secondary", Action = "AddPlayTotal" },
			},
			{
				{ Text = "🏥 +100 cures", Kind = "Secondary", Action = "AddCureStat" },
				{ Text = "🏅 Max badges", Kind = "Secondary", Action = "MaxBadges" },
			},
			{
				{ Text = "🌠 Star Rush", Kind = "Secondary", Action = "AddBoost", Arg = "StarRush" },
				{ Text = "⚡ Quick Hands", Kind = "Secondary", Action = "AddBoost", Arg = "QuickHands" },
				{ Text = "🍀 Lucky Tips", Kind = "Secondary", Action = "AddBoost", Arg = "LuckyTips" },
			},
		},
	},
	{
		Title = "🎓 Tutorial",
		Rows = {
			{
				{ Text = "✅ Finish", Kind = "Secondary", Action = "FinishTutorial" },
				{
					Text = "🔄 Restart",
					Kind = "Destructive",
					Action = "RestartTutorial",
					Confirm = "From the start, with a respawn",
				},
			},
		},
	},
	{
		Title = "🌍 Whole server · alone only",
		Rows = {
			{
				{ Text = "🌙 Night", Kind = "Secondary", Action = "SkipToNight" },
				{ Text = "☀️ Day", Kind = "Secondary", Action = "SkipToDay" },
			},
			{
				{ Text = "❄️ Winter on/off", Kind = "Secondary", Action = "ToggleWinter" },
			},
		},
	},
}

-- Progression v2 (build plan §B8 "Admin"): the 🏢 page.
local BRANCH_SECTIONS: { Section } = {
	{
		Title = "🏢 Branches · your save",
		Rows = {
			{
				{
					Text = "🏢 Rebirth now",
					Kind = "Destructive",
					Action = "Rebirth",
					Confirm = "Your clinic starts over",
				},
				{ Text = "🌳 +3 points", Kind = "Secondary", Action = "AddTreePoints" },
			},
			{
				{ Text = "⬆️ Nurse levels", Kind = "Secondary", Action = "NurseLevels" },
				{ Text = "✨ Charge abilities", Kind = "Secondary", Action = "ChargeAbilities" },
			},
			{
				{ Text = "🚑 Ambulance", Kind = "Secondary", Action = "SpawnAmbulance" },
				{ Text = "🚁 Helicopter", Kind = "Secondary", Action = "SpawnHelicopter" },
			},
		},
	},
	{
		Title = "🌍 Whole server · alone only",
		Rows = {
			{
				{ Text = "🏢 Restock Agency", Kind = "Secondary", Action = "RefillAgency" },
			},
		},
	},
}

-- A scrolling page that fills the space beside the tabs.
local function page(parent: Instance, name: string): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Visible = false
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Step[1])
	pad.PaddingBottom = UDim.new(0, Theme.Space.Gap)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Step[1]) -- scrolling frames clip: keep the buttons' outlines whole
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

function AdminPanel.init(ctx: Types.Ctx)
	local player = Players.LocalPlayer
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = NAME,
		Title = "🛠️ Admin",
		MaxSize = Vector2.new(640, 600),
	})

	local pages: { [string]: ScrollingFrame } = {}
	local firsts: { [string]: GuiObject } = {} -- each page's first button (gamepad focus)

	-- THE tab column: one tab per page.
	local tabView: Modal.Tabs -- (declared first: the select callback below reads it)
	tabView = Modal.tabs(modal, PAGES, function(name: string)
		for pageName, frame in pages do
			frame.Visible = pageName == name
		end
		local shown = pages[name]
		if shown then
			shown.CanvasPosition = Vector2.zero
		end
		modal.Focus = tabView.Buttons[name]
	end)
	for _, spec in PAGES do
		pages[spec.Id] = page(tabView.Content, spec.Id)
	end
	local function show(name: string)
		tabView.select(name)
		-- A gamepad's selection moves with the page (it was on the button that switched pages).
		local focus: GuiObject? = firsts[name]
		local selected = GuiService.SelectedObject
		if focus and selected and selected:IsDescendantOf(modal.Gui) then
			GuiService.SelectedObject = focus
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Asking the server (one request at a time; the reply is the toast)
	--------------------------------------------------------------------------------------------------------------
	local busy = false
	local function ask(button: GuiObject, action: string, arg: any)
		if busy then
			return
		end
		if player:GetAttribute(ATTRIBUTE) ~= true then
			modal.close()
			return
		end
		busy = true
		task.spawn(function()
			local ok, message = Hud.ask(ctx.Remotes.Admin, action, arg)
			busy = false
			if ok then
				ctx.toast(if message ~= "" then message else "✅ Done!")
				Hud.pop(button, 1.08)
				Hud.sound("Chime")
			else
				ctx.toast(if message ~= "" then message else "🔒 Admins only!")
				Hud.shake(button)
			end
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Pages
	--------------------------------------------------------------------------------------------------------------
	local orders: { [string]: number } = {}
	local function nextOrder(name: string): number
		orders[name] = (orders[name] or 0) + 1
		return orders[name]
	end

	local function buildSections(name: string, sections: { Section })
		local parent = pages[name]
		for _, section in sections do
			local title = Kit.label({
				Name = "Section",
				Text = section.Title,
				Font = Theme.DisplayFont,
				TextScaled = true,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = nextOrder(name),
				Parent = parent,
			})
			Kit.textLimit(title, Theme.TextSize.Body)

			for _, acts in section.Rows do
				local row = Instance.new("Frame")
				row.Name = "Row"
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, 0, 0, ROW)
				row.LayoutOrder = nextOrder(name)
				local list = Kit.list(row, Enum.FillDirection.Horizontal, GAP)
				list.HorizontalAlignment = Enum.HorizontalAlignment.Left
				row.Parent = parent

				local count = #acts
				for index, act in acts do
					local button = Kit.button({
						Name = act.Action,
						Kind = act.Kind,
						Text = act.Text,
						TextScaled = true,
						LayoutOrder = index,
						Size = UDim2.new(1 / count, -GAP * (count - 1) / count, 0, ROW),
						Parent = row,
					})
					Kit.textLimit(button, Theme.TextSize.Body)
					if not firsts[name] then
						firsts[name] = button
					end
					button.Activated:Connect(function()
						local line = act.Confirm
						if line then
							-- A reset: THE confirm first ("Not now" focused).
							Hud.confirm(ctx, {
								Title = act.Text,
								Line = line,
								Yes = act.Text,
								Kind = "Destructive",
							}, function()
								ask(button, act.Action, act.Arg)
							end)
						else
							ask(button, act.Action, act.Arg)
						end
					end)
				end
			end
		end
	end

	-- A big card with a portrait, a name and an icon line on the right (the patient and nurse pickers).
	local function card(name: string, id: string, look: any, title: string, right: string, onTap: (GuiObject) -> ())
		local button = Kit.button({
			Name = id,
			Kind = "Secondary",
			LayoutOrder = nextOrder(name),
			Size = UDim2.new(1, 0, 0, CARD_ROW),
			Parent = pages[name],
		})
		if not firsts[name] then
			firsts[name] = button
		end

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.AnchorPoint = Vector2.new(0, 0.5)
		face.Position = UDim2.new(0, Theme.Space.Gap, 0.5, 0)
		face.Size = UDim2.fromOffset(52, 52)
		face.BackgroundColor3 = Theme.Colors.Well
		face.BorderSizePixel = 0
		face.ZIndex = 2
		Kit.corner(face, Theme.Radius.Medium)
		local portrait = Hud.portrait(look)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		face.Parent = button

		local nameLabel = Kit.label({
			Name = "CardName",
			Text = title,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 72, 0.5, 0),
			Size = UDim2.new(1, -72 - 110, 0, 30),
			ZIndex = 2,
			Parent = button,
		})
		Kit.textLimit(nameLabel, Theme.TextSize.Body)

		local info = Kit.label({
			Name = "Info",
			Text = right,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.Space.PadCard, 0.5, 0),
			Size = UDim2.fromOffset(96, 30),
			ZIndex = 2,
			Parent = button,
		})
		Kit.textLimit(info, Theme.TextSize.Button)

		button.Activated:Connect(function()
			onTap(button)
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The tools page and the 🏢 page
	--------------------------------------------------------------------------------------------------------------
	buildSections("Actions", SECTIONS)
	buildSections("Branch", BRANCH_SECTIONS)

	--------------------------------------------------------------------------------------------------------------
	-- The patients page: tap a creature and it's next in your own line
	--------------------------------------------------------------------------------------------------------------
	for _, patientId in data.Patients.Order do
		local patient = data.Patients[patientId]
		local ailment = data.Ailments[patient.Ailment]
		local station = if ailment then data.Stations[ailment.Station] else nil
		local wing = data.Wings[patient.Wing]
		-- What it has, what cures it, and its wing: "🤧→🧪 🌳"
		local needs = (if ailment then ailment.Icon else "")
			.. "→"
			.. (if station then station.Icon else "")
			.. " "
			.. (if wing then wing.Icon else "")
		card(
			"Patients",
			patientId,
			patient.Look,
			(if patient.Night then "🌙 " else "") .. patient.Name,
			needs,
			function(button)
				ask(button, "SpawnPatient", patientId)
			end
		)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The nurses page (Progression v2): tap a nurse and it's yours, free (the roster rules still apply)
	--------------------------------------------------------------------------------------------------------------
	for _, nurseId in data.Nurses.Order do
		local nurse = data.Nurses[nurseId]
		local rarity = rawget(data.Rarities, nurse.Rarity)
		local job = rawget(data.Jobs, nurse.Role)
		local right = (if rarity then rarity.Icon else "") .. " " .. (if job then job.Icon else "")
		card("Nurses", nurseId, nurse.Look, nurse.Icon .. " " .. nurse.Name, right, function(button)
			ask(button, "GiveNurse", nurseId)
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Opening (admins only: the server's attribute; the remote checks again anyway)
	--------------------------------------------------------------------------------------------------------------
	ctx.on("Open", function(name: any)
		if name ~= NAME or player:GetAttribute(ATTRIBUTE) ~= true then
			return
		end
		show("Actions")
		modal.open()
	end)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		if player:GetAttribute(ATTRIBUTE) ~= true then
			modal.close()
		end
	end)
	show("Actions")
end

return AdminPanel
