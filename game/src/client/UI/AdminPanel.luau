--!strict
-- AdminPanel (game/README.md "Admin panel"): the 🛠️ Admin panel for the two developer accounts, to test progression
-- quickly in the live game and in Studio.
--   init(ctx)   opens on ctx.fire("Open", "Admin"): the 🛠️ button in the HUD's ⚙️ panel sends it, and that button
--               only shows while the server has set the player attribute IsAdmin (Server/Admin)
-- The panel is just buttons. Each one asks the Admin remote (action, arg?); the server checks again that you're an
-- admin, validates the action and its argument (Logic/Admin) and answers (ok, message), shown as a toast. Nothing
-- here is trusted, and nothing on screen changes until the server's next Snapshot.
--
-- Two pages in one panel:
--   the actions    your own save (💰 ⭐ rooms, decor, the Book, stories, goals and mail, the tutorial, a patient),
--                  then the whole server's night, day and winter (the server allows those only when you're alone in
--                  it, or in Studio; otherwise its reply says why)
--   the patients   "🤧 Spawn patient…": tap a creature and it's next in your own line
-- Phones: both pages scroll and every button is at least 56 px tall. Motion is Kit's and Hud's, so it honours reduced
-- motion and the ✨ calm switch.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local AdminPanel = {}

local NAME = "Admin" -- the modal, and the "Open" bus name
local ATTRIBUTE = "IsAdmin" -- set by Server/Admin; only steers the UI
local ACCENT = Theme.Colors.Purple
local ROW = Theme.Size.ButtonHeight
local PATIENT_ROW = 68
local GAP = 8

-- One button: an Admin remote call (Action, Arg), or Opens the patient page.
type Act = { Text: string, Kind: string, Action: string?, Arg: number?, Opens: string? }
type Section = { Title: string, Rows: { { Act } } }

local SECTIONS: { Section } = {
	{
		Title = "👤 Your save",
		Rows = {
			{
				{ Text = "+1,000 💰", Kind = "Cash", Action = "AddCash", Arg = 1000 },
				{ Text = "+10,000 💰", Kind = "Cash", Action = "AddCash", Arg = 10000 },
			},
			{
				{ Text = "+10 ⭐", Kind = "Primary", Action = "AddStars", Arg = 10 },
				{ Text = "+100 ⭐", Kind = "Primary", Action = "AddStars", Arg = 100 },
			},
			{
				{ Text = "🏠 All rooms", Kind = "Secondary", Action = "UnlockRooms" },
				{ Text = "🌸 All decor", Kind = "Pink", Action = "AllDecor" },
			},
			{
				{ Text = "📖 Full Book", Kind = "Purple", Action = "CompleteBook" },
				{ Text = "💌 Stories today", Kind = "Pink", Action = "StoriesDue" },
			},
			{
				{ Text = "🎯 Reset goals + 📬", Kind = "Good", Action = "ResetDaily" },
				{ Text = "🤧 Spawn patient…", Kind = "Cyan", Opens = "Patients" },
			},
		},
	},
	{
		Title = "🎓 Tutorial",
		Rows = {
			{
				{ Text = "✅ Finish", Kind = "Good", Action = "FinishTutorial" },
				{ Text = "🔄 Restart", Kind = "Danger", Action = "RestartTutorial" },
			},
		},
	},
	{
		Title = "🌍 Whole server · alone only",
		Rows = {
			{
				{ Text = "🌙 Night", Kind = "Purple", Action = "SkipToNight" },
				{ Text = "☀️ Day", Kind = "Primary", Action = "SkipToDay" },
			},
			{
				{ Text = "❄️ Winter on/off", Kind = "Cyan", Action = "ToggleWinter" },
			},
		},
	},
}

local function textLimit(gui: GuiObject, max: number, min: number?)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min or 12
	limit.Parent = gui
end

-- A scrolling page that fills the panel's body (like the Shop's).
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
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 3) -- scrolling frames clip: keep the buttons' outlines whole
	pad.PaddingRight = UDim.new(0, 12)
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
		Accent = ACCENT,
		MaxSize = Vector2.new(560, 600),
	})

	local actions = page(modal.Body, "Actions")
	local patients = page(modal.Body, "Patients")

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
	local firstAction: GuiObject? = nil
	local back: TextButton

	local function show(name: string)
		local onPatients = name == "Patients"
		actions.Visible = not onPatients
		patients.Visible = onPatients
		local shown = if onPatients then patients else actions
		shown.CanvasPosition = Vector2.zero
		local focus: GuiObject? = if onPatients then back else firstAction
		modal.Focus = focus
		-- A gamepad's selection moves with the page (it was on the button that switched pages).
		local selected = GuiService.SelectedObject
		if focus and selected and selected:IsDescendantOf(modal.Gui) then
			GuiService.SelectedObject = focus
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The actions page
	--------------------------------------------------------------------------------------------------------------
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	for _, section in SECTIONS do
		local title = Kit.label({
			Name = "Section",
			Text = section.Title,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = nextOrder(),
			Parent = actions,
		})
		textLimit(title, 22)

		for _, acts in section.Rows do
			local row = Instance.new("Frame")
			row.Name = "Row"
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, ROW)
			row.LayoutOrder = nextOrder()
			local list = Kit.list(row, Enum.FillDirection.Horizontal, GAP)
			list.HorizontalAlignment = Enum.HorizontalAlignment.Left
			row.Parent = actions

			local count = #acts
			for index, act in acts do
				local button = Kit.button({
					Name = act.Action or act.Opens or "Button",
					Kind = act.Kind,
					Text = act.Text,
					TextScaled = true,
					LayoutOrder = index,
					Size = UDim2.new(1 / count, -GAP * (count - 1) / count, 0, ROW),
					Parent = row,
				})
				textLimit(button, Theme.TextSize.Body, 14)
				if not firstAction then
					firstAction = button
				end
				local action, opens = act.Action, act.Opens
				button.Activated:Connect(function()
					if opens then
						show(opens)
					elseif action then
						ask(button, action, act.Arg)
					end
				end)
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The patients page: tap a creature and it's next in your own line
	--------------------------------------------------------------------------------------------------------------
	back = Kit.button({
		Name = "Back",
		Kind = "Quiet",
		Text = "⬅️ Back",
		TextScaled = true,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, ROW),
		Parent = patients,
	})
	textLimit(back, Theme.TextSize.Body, 14)
	back.Activated:Connect(function()
		show("Actions")
	end)

	for index, patientId in data.Patients.Order do
		local patient = data.Patients[patientId]
		local ailment = data.Ailments[patient.Ailment]
		local station = if ailment then data.Stations[ailment.Station] else nil
		local wing = data.Wings[patient.Wing]

		local button = Kit.button({
			Name = patientId,
			Kind = "Card",
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, PATIENT_ROW),
			Parent = patients,
		})

		local face = Instance.new("Frame")
		face.Name = "Face"
		face.AnchorPoint = Vector2.new(0, 0.5)
		face.Position = UDim2.new(0, 8, 0.5, 0)
		face.Size = UDim2.fromOffset(52, 52)
		face.BackgroundColor3 = Kit.lighten(ACCENT, 0.7)
		face.BorderSizePixel = 0
		face.ZIndex = 2
		Kit.corner(face, 12)
		Kit.stroke(face, Theme.Colors.Outline, 2.5)
		Palette.candyGradient(face)
		local portrait = Hud.portrait(patient.Look)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		face.Parent = button

		local nameLabel = Kit.label({
			Name = "PatientName",
			Text = (if patient.Night then "🌙 " else "") .. patient.Name,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 72, 0.5, 0),
			Size = UDim2.new(1, -72 - 110, 0, 30),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(nameLabel, 22)

		-- What it has, what cures it, and its wing: "🤧→🧪 🌳"
		local needs = Kit.label({
			Name = "Needs",
			Text = (if ailment then ailment.Icon else "")
				.. "→"
				.. (if station then station.Icon else "")
				.. " "
				.. (if wing then wing.Icon else ""),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(96, 30),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(needs, 24)

		button.Activated:Connect(function()
			ask(button, "SpawnPatient", patientId)
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
