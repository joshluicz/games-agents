--!strict
-- AdminPanel (game/README.md "Admin panel"): the 🛠️ Admin panel for the two developer accounts, to test progression
-- quickly in the live game and in Studio.
--   init(ctx)   opens on ctx.fire("Open", "Admin"): the 🛠️ button in the HUD's ⚙️ panel sends it, and that button
--               only shows while the server has set the player attribute IsAdmin (Server/Admin)
-- The panel is just buttons. Each one asks the Admin remote (action, arg?); the server checks again that you're an
-- admin, validates the action and its argument (Logic/Admin) and answers (ok, message), shown as a toast. Nothing
-- here is trusted, and nothing on screen changes until the server's next Snapshot.
--
-- Four pages in one panel:
--   the actions    your own save (💰 ⭐ rooms, decor, the Book, stories, goals and mail, play time, badges and
--                  boosts, the tutorial, a patient), then the whole server's night, day and winter (the server allows
--                  those only when you're alone in it, or in Studio; otherwise its reply says why)
--   🏢 branches    Progression v2 (build plan §B8): 🏢 Rebirth now, 🌳 +3 points, ⬆️ Nurse levels, ✨ Charge
--                  abilities, 🚑 Ambulance, 🚁 Helicopter, and the whole server's 🏢 Restock Agency. A system that hasn't
--                  landed yet answers "Coming soon!"
--   the patients   "🤧 Spawn patient…": tap a creature and it's next in your own line
--   the nurses     "🎁 Give nurse…": tap a nurse and it's yours, free (the roster rules still apply)
-- Phones: every page scrolls and every button is at least 56 px tall. Motion is Kit's and Hud's, so it honours reduced
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
local CARD_ROW = 68
local GAP = 8

-- One button: an Admin remote call (Action, Arg), or Opens another page.
type Act = { Text: string, Kind: string, Action: string?, Arg: (number | string)?, Opens: string? }
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
			{
				{ Text = "🏢 Branch tools…", Kind = "Purple", Opens = "Branch" },
				{ Text = "🎁 Give nurse…", Kind = "Cyan", Opens = "Nurses" },
			},
		},
	},
	{
		Title = "⏱️ Play time · badges · boosts",
		Rows = {
			{
				{ Text = "🎁 +10 min today", Kind = "Pink", Action = "AddPlayToday" },
				{ Text = "⏱️ +5 h total", Kind = "Purple", Action = "AddPlayTotal" },
			},
			{
				{ Text = "🏥 +100 cures", Kind = "Secondary", Action = "AddCureStat" },
				{ Text = "🏅 Max badges", Kind = "Primary", Action = "MaxBadges" },
			},
			{
				{ Text = "🌠 Star Rush", Kind = "Purple", Action = "AddBoost", Arg = "StarRush" },
				{ Text = "⚡ Quick Hands", Kind = "Cyan", Action = "AddBoost", Arg = "QuickHands" },
				{ Text = "🍀 Lucky Tips", Kind = "Good", Action = "AddBoost", Arg = "LuckyTips" },
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

-- Progression v2 (build plan §B8 "Admin"): the 🏢 page.
local BRANCH_SECTIONS: { Section } = {
	{
		Title = "🏢 Branches · your save",
		Rows = {
			{
				{ Text = "🏢 Rebirth now", Kind = "Purple", Action = "Rebirth" },
				{ Text = "🌳 +3 points", Kind = "Good", Action = "AddTreePoints" },
			},
			{
				{ Text = "⬆️ Nurse levels", Kind = "Primary", Action = "NurseLevels" },
				{ Text = "✨ Charge abilities", Kind = "Pink", Action = "ChargeAbilities" },
			},
			{
				{ Text = "🚑 Ambulance", Kind = "Danger", Action = "SpawnAmbulance" },
				{ Text = "🚁 Helicopter", Kind = "Cyan", Action = "SpawnHelicopter" },
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

	local pages: { [string]: ScrollingFrame } = {
		Actions = page(modal.Body, "Actions"),
		Branch = page(modal.Body, "Branch"),
		Patients = page(modal.Body, "Patients"),
		Nurses = page(modal.Body, "Nurses"),
	}
	local firsts: { [string]: GuiObject } = {} -- each page's first button (gamepad focus)

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
	local function show(name: string)
		for pageName, frame in pages do
			frame.Visible = pageName == name
		end
		local shown = pages[name]
		if shown then
			shown.CanvasPosition = Vector2.zero
		end
		local focus: GuiObject? = firsts[name]
		modal.Focus = focus
		-- A gamepad's selection moves with the page (it was on the button that switched pages).
		local selected = GuiService.SelectedObject
		if focus and selected and selected:IsDescendantOf(modal.Gui) then
			GuiService.SelectedObject = focus
		end
	end

	local orders: { [string]: number } = {}
	local function nextOrder(name: string): number
		orders[name] = (orders[name] or 0) + 1
		return orders[name]
	end

	local function backButton(name: string)
		local back = Kit.button({
			Name = "Back",
			Kind = "Quiet",
			Text = "⬅️ Back",
			TextScaled = true,
			LayoutOrder = nextOrder(name),
			Size = UDim2.new(1, 0, 0, ROW),
			Parent = pages[name],
		})
		textLimit(back, Theme.TextSize.Body, 14)
		back.Activated:Connect(function()
			show("Actions")
		end)
		firsts[name] = back
	end

	local function buildSections(name: string, sections: { Section })
		local parent = pages[name]
		for _, section in sections do
			local title = Kit.label({
				Name = "Section",
				Text = section.Title,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = nextOrder(name),
				Parent = parent,
			})
			textLimit(title, 22)

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
						Name = act.Action or act.Opens or "Button",
						Kind = act.Kind,
						Text = act.Text,
						TextScaled = true,
						LayoutOrder = index,
						Size = UDim2.new(1 / count, -GAP * (count - 1) / count, 0, ROW),
						Parent = row,
					})
					textLimit(button, Theme.TextSize.Body, 14)
					if not firsts[name] then
						firsts[name] = button
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
	end

	-- A big card with a portrait, a name and an icon line on the right (the patient and nurse pickers).
	local function card(name: string, id: string, look: any, title: string, right: string, onTap: (GuiObject) -> ())
		local button = Kit.button({
			Name = id,
			Kind = "Card",
			LayoutOrder = nextOrder(name),
			Size = UDim2.new(1, 0, 0, CARD_ROW),
			Parent = pages[name],
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
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 72, 0.5, 0),
			Size = UDim2.new(1, -72 - 110, 0, 30),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(nameLabel, 22)

		local info = Kit.label({
			Name = "Info",
			Text = right,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(96, 30),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(info, 24)

		button.Activated:Connect(function()
			onTap(button)
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The actions page and the 🏢 page
	--------------------------------------------------------------------------------------------------------------
	buildSections("Actions", SECTIONS)
	backButton("Branch")
	buildSections("Branch", BRANCH_SECTIONS)

	--------------------------------------------------------------------------------------------------------------
	-- The patients page: tap a creature and it's next in your own line
	--------------------------------------------------------------------------------------------------------------
	backButton("Patients")
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
	backButton("Nurses")
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
