--!strict
-- The payoff moments (build plan Task 7; depth update T6). Client only; nothing here changes game state.
--   Cured remote   sparkles, candy confetti, a ring and little hearts at the patient, a "+💰 n" / "+⭐ n" pop that
--                  floats up, and a chime; then the coins (and the owner's stars) fly from the patient into the HUD's
--                  💰 and ⭐ pills (Hud.fly), which roll up as they land. A NEW PAGE banner when the Book got a page.
--   A new room     sparkles and confetti across its floor, and the big NEW ROOM celebration screen (the bus
--                  "Celebrate" with Kind "Room", plus Room = <RoomId> for its name; UI/Celebrate shows it).
--   A set done     a SET COMPLETE banner when a Book wing's set reward lands in your Decor.Owned.
--   Decor placed   a puff of sparkles and confetti, and a soft thud where it lands (when your Decor.Placed changes).
--   A heart        a 💖 floats off your clinic sign when someone leaves you a heart.
-- Mini-games (bus events from UI/MiniGames): "TreatStart" remembers where the patient is (or the dispensary, for a
-- Dispense card); "MiniGameRated" puts a sparkle over it for a Good and a bigger burst for a Perfect (an OK gets
-- nothing extra: it still treats); "TreatDone" with a tip pops "💰 +n" (and the 🔥 combo) over the patient and flies
-- the coins into 💰, and an exam's revealed case (TreatOutcome.Case) floats its icon up over the patient.
-- The Cured remote, the module's name and the "cure pop" in the code are internal names (the Real Clinic's §12: the
-- game's words say treat; nothing here shows the word).
--
-- Candy pop (memory-20261116-007): saturated colours, chunky outlined text, banners with the reward's icon on
-- turning rays. Still kind to kids on phones: nothing flashes or strobes, no camera shake, and every motion honours
-- Reduce effects: the player attribute "ReduceEffects" (client-only, set by Feel/Atmosphere's toggle; falls back to
-- the device's Reduced Motion setting) cuts the particles and the confetti, drops the ring, the pop scale and the
-- banner shine, and holds the rays still.
--
-- Progression v2 (build plan §C T8): the cure pop grows a line per bonus that paid: "🌟 Golden!" (a Golden patient,
-- with gold sparkles and the Golden chime), "🚑 ×3" / "🚁 ×4" (an ambulance or helicopter patient), "+20% 🛗" (you
-- or a Porter rode it up to its bed). The numbers come from Config, the facts from the Cured payload (Urgent,
-- Escorted) or, when the server sends none, the patient model's own attributes. The rules are the pure BONUS block (tests/Juice).
--
-- Bus events fired: "Sound" (Chime, Sparkle, Fanfare, Pop, Thud, Heart, Golden): Feel/Sounds plays them;
-- "Celebrate" (Room).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))

local CureFX = {}

-- Built-in particle textures (checked in the Player's content folder, 2026-11-16).
local TEXTURE = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds", -- a four-point twinkle
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds", -- a soft thin ring
	Confetti = "rbxasset://textures/particles/SquareParticle.png", -- a plain square
}

-- Sparkle colours per mood, all full candy: gold and pink by default, gold for Sparkly, cyan for Frosty, purple at
-- night, lime for a new room.
local PALETTES: { [string]: { Color3 } } = {
	Default = { Theme.Colors.Cash, Theme.Colors.Pink },
	Sparkly = { Theme.Colors.Star, Theme.Colors.Paper },
	Frosty = { Theme.Colors.Cyan, Theme.Colors.Paper },
	Night = { Theme.Colors.Purple, Theme.Colors.Cash },
	Room = { Theme.Colors.Good, Theme.Colors.Cash },
	Golden = { Theme.Colors.Cash, Theme.Colors.Star },
}

-- BEGIN BONUS
local Bonus = {}

export type BonusLine = { Text: string, Kind: string }

local function finiteNumber(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- 3 -> "3", 2.5 -> "2.5"
local function short(n: number): string
	if n == math.floor(n) then
		return tostring(math.floor(n))
	end
	return (string.gsub(string.format("%.1f", n), "%.0$", ""))
end

local function section(cfg: any, key: string): any
	local value = if type(cfg) == "table" then cfg[key] else nil
	return if type(value) == "table" then value else {}
end

-- The bonus lines for one visit, in order: Golden, the urgent multiplier and the escort. `info` is the
-- Cured payload; `attrs` the patient model's attributes ({ Urgent, Escorted }) for any fact the payload
-- doesn't carry; `cfg` is Config (AE/VIP CashMultiplier, Escort.CashBonus). Kind picks the colour.
function Bonus.lines(info: any, attrs: any, cfg: any): { BonusLine }
	local out: { BonusLine } = {}
	if type(info) ~= "table" then
		return out
	end
	local fallback = if type(attrs) == "table" then attrs else {}
	local function fact(key: string): any
		local value = info[key]
		if value == nil then
			value = fallback[key]
		end
		return value
	end
	if info.Variant == "Golden" then
		table.insert(out, { Text = "🌟 Golden!", Kind = "Golden" })
	end
	local urgent = fact("Urgent")
	if urgent == "AE" or urgent == "VIP" then
		local multiplier = finiteNumber(section(cfg, urgent).CashMultiplier)
		if multiplier and multiplier > 1 then
			local icon = if urgent == "AE" then "🚑" else "🚁"
			table.insert(out, { Text = icon .. " ×" .. short(multiplier), Kind = urgent })
		end
	end
	local function percent(key: string, field: string, icon: string, kind: string)
		local share = finiteNumber(section(cfg, key)[field])
		if share and share > 0 then
			table.insert(out, { Text = "+" .. short(math.floor(share * 100 + 0.5)) .. "% " .. icon, Kind = kind })
		end
	end
	if fact("Escorted") == true then
		percent("Escort", "CashBonus", "🛗", "Escort")
	end
	return out
end
-- END BONUS

local BONUS_COLORS: { [string]: Color3 } = {
	Golden = Theme.Colors.Cash,
	AE = Theme.Colors.Danger,
	VIP = Theme.Colors.Purple,
	Escort = Theme.Colors.Secondary,
}
-- Confetti: one emitter per colour, so every burst is a mix of the candy set.
local CONFETTI = { Theme.Colors.Pink, Theme.Colors.Cash, Theme.Colors.Cyan, Theme.Colors.Good, Theme.Colors.Purple }

local MAX_LIVE_FX = 12 -- world effects at once (a cure uses 3); a crowd of helpers can't flood the screen
local MAX_BANNERS = 3 -- queued banners; more are dropped
local POP_SECONDS = 1.3
local BANNER_HOLD = 2.2

local player = Players.LocalPlayer
local ctx: Types.Ctx
local liveFx = 0

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function calm(): boolean
	local value = player:GetAttribute("ReduceEffects")
	if value == nil then
		return Kit.reducedMotion()
	end
	return value == true
end

local function sound(name: string, volumeScale: number?)
	ctx.fire("Sound", name, volumeScale)
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function myPlot(): Model?
	local index = player:GetAttribute("PlotIndex")
	local clinics = Workspace:FindFirstChild("Clinics")
	if type(index) ~= "number" or not clinics then
		return nil
	end
	local plot = clinics:FindFirstChild("Plot_" .. index)
	return if plot and plot:IsA("Model") then plot else nil
end

-- The UserId that owns the clinic plot a world position is on (nil if it's not on a plot).
local function ownerAt(position: Vector3): number?
	local clinics = Workspace:FindFirstChild("Clinics")
	if not clinics then
		return nil
	end
	local half = ctx.Config.Town.PlotSize / 2
	for _, plot in clinics:GetChildren() do
		if plot:IsA("Model") then
			local p = plot:GetPivot():PointToObjectSpace(position)
			if math.abs(p.X) <= half and math.abs(p.Z) <= half then
				local owner = plot:GetAttribute("OwnerUserId")
				return if type(owner) == "number" then owner else nil
			end
		end
	end
	return nil
end

-- The cured patient's own facts, while its model is still on the plot (the server's Patients sets them): the one
-- with that PatientId nearest the cure, within a few studs. Empty when it's gone already.
local function patientFacts(position: Vector3, patientId: string): { [string]: any }
	local clinics = Workspace:FindFirstChild("Clinics")
	if not clinics or patientId == "" then
		return {}
	end
	local half = ctx.Config.Town.PlotSize / 2
	for _, plot in clinics:GetChildren() do
		if plot:IsA("Model") then
			local p = plot:GetPivot():PointToObjectSpace(position)
			if math.abs(p.X) <= half and math.abs(p.Z) <= half then
				local folder = plot:FindFirstChild("Patients")
				local best: Instance? = nil
				local bestDistance = 12
				for _, model in (if folder then folder:GetChildren() else {}) do
					if model:IsA("Model") and model:GetAttribute("PatientId") == patientId then
						local distance = (model:GetPivot().Position - position).Magnitude
						if distance < bestDistance then
							best, bestDistance = model, distance
						end
					end
				end
				if not best then
					return {}
				end
				return {
					Urgent = best:GetAttribute("Urgent"),
					Escorted = best:GetAttribute("Escorted"),
				}
			end
		end
	end
	return {}
end

-- A throwaway Attachment in Terrain: world-space effects that clean themselves up.
local function anchorAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "CureFX"
	attachment.Position = position -- Terrain sits at the origin, so this is the world position
	attachment.Parent = Workspace.Terrain
	liveFx += 1
	task.delay(lifetime, function()
		liveFx -= 1
		attachment:Destroy()
	end)
	return attachment
end

local function sequence(from: number, to: number): NumberSequence
	return NumberSequence.new(from, to)
end

------------------------------------------------------------------------------------------------------------------
-- World effects
------------------------------------------------------------------------------------------------------------------

local function burst(position: Vector3, palette: { Color3 }, count: number, spread: number?)
	if liveFx >= MAX_LIVE_FX then
		return
	end
	local quiet = calm()
	local attachment = anchorAt(position, 1.6)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = TEXTURE.Sparkle
	sparkles.Color = ColorSequence.new(palette[1], palette[2] or palette[1])
	sparkles.LightEmission = 0.45
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Lifetime = NumberRange.new(0.6, 1.0)
	sparkles.Speed = NumberRange.new(4, 8)
	sparkles.SpreadAngle = Vector2.new(spread or 65, spread or 65)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Acceleration = Vector3.new(0, -7, 0)
	sparkles.Drag = 2
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-120, 120)
	sparkles.Enabled = false
	sparkles.Parent = attachment
	sparkles:Emit(if quiet then math.max(3, math.floor(count / 3)) else count)

	if not quiet then
		-- Confetti: tumbling candy squares that pop up and fall (no light emission, so nothing flashes).
		local pieces = math.max(2, math.floor(count / 5))
		for _, color in CONFETTI do
			local confetti = Instance.new("ParticleEmitter")
			confetti.Name = "Confetti"
			confetti.Texture = TEXTURE.Confetti
			confetti.Color = ColorSequence.new(color)
			confetti.LightEmission = 0
			confetti.LightInfluence = 0
			confetti.Size = NumberSequence.new(0.24)
			confetti.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.75, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			confetti.Lifetime = NumberRange.new(0.9, 1.3)
			confetti.Speed = NumberRange.new(7, 11)
			confetti.SpreadAngle = Vector2.new(spread or 50, spread or 50)
			confetti.EmissionDirection = Enum.NormalId.Top
			confetti.Acceleration = Vector3.new(0, -16, 0)
			confetti.Drag = 1.5
			confetti.Rotation = NumberRange.new(0, 360)
			confetti.RotSpeed = NumberRange.new(-300, 300)
			confetti.Enabled = false
			confetti.Parent = attachment
			confetti:Emit(pieces)
		end

		local ring = Instance.new("ParticleEmitter")
		ring.Texture = TEXTURE.Ring
		ring.Color = ColorSequence.new(palette[2] or palette[1])
		ring.LightEmission = 0.3
		ring.LightInfluence = 0
		ring.Size = sequence(0.8, 5.5)
		ring.Transparency = sequence(0.35, 1)
		ring.Lifetime = NumberRange.new(0.45)
		ring.Speed = NumberRange.new(0)
		ring.Enabled = false
		ring.Parent = attachment
		ring:Emit(1)
	end
end

-- Emoji that drift up and fade (hearts after a cure, the heart off a sign). AlwaysOnTop off: they sit in the world.
local function floaters(position: Vector3, icons: { string })
	if liveFx >= MAX_LIVE_FX then
		return
	end
	local quiet = calm()
	local attachment = anchorAt(position, 1.8)
	local count = if quiet then 1 else #icons
	for index = 1, count do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(1.3, 1.3)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.StudsOffsetWorldSpace = Vector3.new((index - (count + 1) / 2) * 0.9, 0, 0)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Theme.Font
		label.Text = icons[index]
		label.Parent = gui
		gui.Parent = attachment

		local delay = (index - 1) * 0.08
		local rise = Vector3.new((index - (count + 1) / 2) * 1.6, 3 + math.random() * 0.8, 0)
		task.delay(delay, function()
			tween(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				StudsOffsetWorldSpace = rise,
			})
			tween(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9), {
				TextTransparency = 1,
			})
		end)
	end
end

-- The "+💰 18 / +⭐ 1" pop. Pixel-sized and always on top, so it reads on a phone at any distance.
local function moneyPop(position: Vector3, lines: { { Text: string, Color: Color3 } })
	if #lines == 0 then
		return
	end
	local quiet = calm()
	local attachment = anchorAt(position, POP_SECONDS + 0.2)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 46 * #lines) -- the chunky display font is wide
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	local scale = Instance.new("UIScale")
	scale.Scale = if quiet then 1 else 0.35
	scale.Parent = gui
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui

	local labels = {}
	local strokes = {}
	for index, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = index
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 46)
		label.Font = Theme.DisplayFont
		label.TextSize = 38
		label.TextColor3 = line.Color
		label.Text = line.Text
		local stroke = Palette.outlineText(label, Theme.Size.StrokeLarge)
		label.Parent = gui
		table.insert(labels, label)
		table.insert(strokes, stroke)
	end
	gui.Parent = attachment

	local rise = if quiet then 1.8 else 3.5
	tween(gui, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 2.5 + rise, 0),
	})
	if not quiet then
		local grow = tween(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 })
		grow.Completed:Once(function()
			tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		end)
	end
	local fadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, POP_SECONDS - 0.4)
	for _, label in labels do
		tween(label, fadeInfo, { TextTransparency = 1 })
	end
	for _, stroke in strokes do
		tween(stroke, fadeInfo, { Transparency = 1 })
	end
end

------------------------------------------------------------------------------------------------------------------
-- Banners (NEW PAGE, NEW ROOM): one at a time, top-centre under the toasts
------------------------------------------------------------------------------------------------------------------

-- Icon: the reward's emoji, in a white bubble on the banner's top edge with rays behind it. Sound: played when the
-- banner shows (rather than when it's queued), for one that waits behind another.
type Banner = { Icon: string, Title: string, Sub: string, Accent: Color3, Sound: string? }

local BADGE = 64 -- the icon bubble, px

local screen: ScreenGui? = nil
local queue: { Banner } = {}
local showing = false

local function bannerScreen(): ScreenGui
	local existing = screen
	if existing and existing.Parent then
		return existing
	end
	local created = Kit.screen("CureFX", Theme.DisplayOrder.Fx)
	screen = created
	return created
end

-- Fades every fill, text and outline in a banner together.
local function fadeAll(root: GuiObject, info: TweenInfo)
	local items: { Instance } = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		if item:IsA("TextLabel") then
			tween(item, info, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif item:IsA("Frame") then
			tween(item, info, { BackgroundTransparency = 1 })
		elseif item:IsA("UIStroke") then
			tween(item, info, { Transparency = 1 })
		end
	end
end

local function showBanner(banner: Banner)
	local quiet = calm()
	if banner.Sound then
		sound(banner.Sound)
	end
	-- A candy slab in the banner's colour: thick dark outline, gradient, gloss, white outlined text.
	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.29)
	frame.Size = UDim2.new(0.86, 0, 0, 112)
	frame.BackgroundColor3 = Kit.lighten(banner.Accent, 0.08)
	frame.BorderSizePixel = 0
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(440, 112)
	limit.Parent = frame
	Kit.corner(frame, Theme.Size.CornerLarge)
	Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(frame)
	Kit.gloss(frame, 10)

	-- The reward's icon on the top edge, on turning rays (Kit.rays holds still with reduced motion).
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0)
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.ZIndex = 1
	badge.Parent = frame
	Kit.rays(badge, Theme.Colors.Cash)
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.BackgroundColor3 = Theme.Colors.Paper
	bubble.BorderSizePixel = 0
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.ZIndex = 1
	Kit.corner(bubble, BADGE / 2)
	Kit.stroke(bubble, Theme.Colors.Outline, Theme.Size.Stroke)
	bubble.Parent = badge
	Kit.label({
		Name = "Icon",
		Text = banner.Icon,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		Parent = bubble,
	})

	local title = Kit.label({
		Name = "Title",
		Text = banner.Title,
		TextSize = 44,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BADGE / 2 + 2),
		Size = UDim2.new(1, -24, 0, 42),
		TextWrapped = false,
		TextScaled = true,
		ZIndex = 2,
		Parent = frame,
	})
	Kit.textLimit(title, 44) -- never under 18 px
	Kit.outline(title, Theme.Size.StrokeLarge)
	local sub = Kit.label({
		Name = "Sub",
		Text = banner.Sub,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.OnColor,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BADGE / 2 + 44),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 2,
		Parent = frame,
	})
	Kit.outline(sub, 2)

	-- A slow sheen that slides across once (not a flash), under the text.
	local shine: Frame? = nil
	if not quiet then
		local sheen = Instance.new("Frame")
		sheen.Name = "Shine"
		sheen.Size = UDim2.fromScale(1, 1)
		sheen.BackgroundColor3 = Color3.new(1, 1, 1)
		sheen.BorderSizePixel = 0
		sheen.ZIndex = 0
		Kit.corner(sheen, Theme.Size.CornerLarge)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 20
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Offset = Vector2.new(-1, 0)
		gradient.Parent = sheen
		sheen.Parent = frame
		task.delay(0.25, function()
			tween(gradient, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Offset = Vector2.new(1, 0),
			})
		end)
		shine = sheen
	end

	frame.Parent = bannerScreen()
	Kit.popIn(frame)
	task.delay(0.2, Kit.bump, badge) -- the reward icon springs once the banner lands
	task.wait(BANNER_HOLD)

	if shine then
		shine:Destroy()
	end
	fadeAll(frame, Theme.Tween.Fade)
	Kit.popOut(frame)
	task.wait(0.3)
	frame:Destroy()
end

local function banner(item: Banner)
	if #queue >= MAX_BANNERS then
		return
	end
	table.insert(queue, item)
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local nextBanner = table.remove(queue, 1) :: Banner
			local ok, err = pcall(showBanner, nextBanner)
			if not ok then
				warn("[CureFX] banner failed:", err)
			end
		end
		showing = false
	end)
end

------------------------------------------------------------------------------------------------------------------
-- The cure
------------------------------------------------------------------------------------------------------------------

local function creatureName(patientId: string): string
	local patient = ctx.Data.Patients[patientId]
	if patient then
		return patient.Name
	end
	local regular = ctx.Data.Regulars[patientId]
	return if regular then regular.Name else ""
end

local function onCured(info: any)
	if type(info) ~= "table" then
		return
	end
	local patientId = if type(info.PatientId) == "string" then info.PatientId else ""
	local variant = if type(info.Variant) == "string" and ctx.Data.Variants[info.Variant] then info.Variant else nil
	local cash = if type(info.Cash) == "number" then math.floor(info.Cash) else 0
	local stars = if type(info.Stars) == "number" then math.floor(info.Stars) else 0
	local position = if typeof(info.Position) == "Vector3" then info.Position :: Vector3 else nil

	-- Cure.resolve sends each player only what they got: the helper the cash, the clinic's owner the Stars (both
	-- when they're the same player). The plot check is a second guard in case both ever get the same payload.
	local iHelped = info.Helper == player.UserId
	local owner = if position then ownerAt(position) else nil
	local ownClinic = owner == nil or owner == player.UserId

	local lines = {}
	if iHelped and cash > 0 then
		local variantIcon = if variant then " " .. ctx.Data.Variants[variant].Icon else ""
		table.insert(lines, { Text = "💰 +" .. cash .. variantIcon, Color = Theme.Colors.Cash })
	end
	if (ownClinic or not iHelped) and stars > 0 then
		local helped = if iHelped then "" else " 🤝"
		table.insert(lines, { Text = "⭐ +" .. stars .. helped, Color = Theme.Colors.Star })
	end

	-- Progression v2: a line for each bonus that paid (Golden, 🚑/🚁, 🛗), for whoever saw the money.
	if (iHelped or ownClinic) and position then
		local facts = if info.Urgent == nil or info.Escorted == nil then patientFacts(position, patientId) else {}
		for index, line in Bonus.lines(info, facts, ctx.Config) do
			if index > 3 then
				break
			end
			table.insert(lines, { Text = line.Text, Color = BONUS_COLORS[line.Kind] or Theme.Colors.Primary })
		end
	end

	if position then
		local mood = if variant == "Sparkly"
				or variant == "Frosty"
				or variant == "Golden"
			then variant
			elseif Workspace:GetAttribute("IsNight") == true then "Night"
			else "Default"
		burst(
			position + Vector3.new(0, 1.5, 0),
			PALETTES[mood :: string] or PALETTES.Default,
			if variant then 18 else 14
		)
		floaters(position + Vector3.new(0, 2, 0), { "💖", "✨", "💖" })
		moneyPop(position, lines)
		-- The pay flies home: coins into 💰 (the helper), stars into ⭐ (the owner).
		local from = position + Vector3.new(0, 3, 0)
		if iHelped and cash > 0 then
			task.delay(0.25, Hud.fly, from, "💰", "Cash", Kit.Juice.coins(cash))
		end
		if (ownClinic or not iHelped) and stars > 0 then
			task.delay(0.4, Hud.fly, from, "⭐", "Stars", math.clamp(stars + 2, 3, 6))
		end
	end

	sound("Pop")
	sound("Chime", if iHelped then 1 else 0.7)
	if variant == "Sparkly" then
		task.delay(0.3, sound, "Sparkle")
	elseif variant == "Golden" then
		task.delay(0.3, sound, "Golden")
	end

	if info.NewPage == true and iHelped then
		local sub = creatureName(patientId)
		if variant then
			sub ..= " " .. ctx.Data.Variants[variant].Icon
		end
		task.delay(0.35, function()
			sound("Fanfare")
			banner({ Icon = "📖", Title = "NEW PAGE!", Sub = sub, Accent = Theme.Colors.Purple }) -- uirules: allow HeaderColor
		end)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Rooms you just got, decor you just placed, hearts on your sign
------------------------------------------------------------------------------------------------------------------

-- Waits (briefly) for a child of `folder` that passes `match`; nil if it doesn't stream in.
local function waitForChild(folder: Instance, match: (Instance) -> boolean, timeout: number): Instance?
	for _, child in folder:GetChildren() do
		if match(child) then
			return child
		end
	end
	local found: Instance? = nil
	local done = false
	local connection = folder.ChildAdded:Connect(function(child)
		if not done and match(child) then
			found = child
			done = true
		end
	end)
	local deadline = os.clock() + timeout
	while not done and os.clock() < deadline do
		task.wait(0.1)
	end
	done = true
	connection:Disconnect()
	return found
end

local function celebrateRoom(roomId: string)
	local room = ctx.Data.Rooms[roomId]
	if not room then
		return
	end
	-- The big celebration screen (UI/Celebrate plays its fanfare). Room is an extra field Celebrate reads for the name.
	ctx.fire("Celebrate", { Kind = "Room", Title = "New room!", Icon = room.Icon, Room = roomId })

	local plot = myPlot()
	local rooms = plot and plot:FindFirstChild("Rooms")
	if not rooms then
		return
	end
	local model = waitForChild(rooms, function(child)
		return child.Name == "Room_" .. roomId
	end, 6)
	if not (model and model:IsA("Model")) then
		return
	end
	local cf, size = model:GetBoundingBox()
	local floorY = cf.Position.Y - size.Y / 2 + 1
	for index, offset in { Vector3.new(-0.3, 0, 0), Vector3.new(0.3, 0, 0.2), Vector3.new(0, 0, -0.3) } do
		local at = cf * Vector3.new(offset.X * size.X, 0, offset.Z * size.Z)
		task.delay((index - 1) * 0.15, burst, Vector3.new(at.X, floorY, at.Z), PALETTES.Room, 16, 80)
	end
end

-- The Book wing whose set reward this decor is (Data/Wings SetReward), if any.
local function setRewardWing(decorId: string): string?
	local wings = (ctx.Data :: any).Wings
	for _, wingId in wings.Order do
		if wings[wingId].SetReward == decorId then
			return wingId
		end
	end
	return nil
end

-- A wing's set reward just landed: the server's toast says it, this celebrates it. It queues after the NEW PAGE
-- banner of the cure that finished the set, so its fanfare plays when it shows.
local function celebrateSet(wingId: string, decorId: string)
	local wing = (ctx.Data :: any).Wings[wingId]
	local decor = ctx.Data.Decor[decorId]
	if not wing or not decor then
		return
	end
	banner({
		Icon = decor.Icon,
		Title = "SET COMPLETE!",
		Sub = wing.Icon .. " " .. wing.Name,
		Accent = Theme.Colors.Primary, -- uirules: allow HeaderColor (a cure banner, not a panel header)
		Sound = "Fanfare",
	})
end

local function celebrateDecor(slotKey: string, decorId: string)
	local plot = myPlot()
	local folder = plot and plot:FindFirstChild("Decor")
	if not folder then
		return
	end
	local model = waitForChild(folder, function(child)
		return child:GetAttribute("SlotKey") == slotKey and child:GetAttribute("DecorId") == decorId
	end, 4)
	if not (model and model:IsA("Model")) then
		return
	end
	local cf, size = model:GetBoundingBox()
	sound("Thud")
	sound("Pop")
	burst(cf.Position - Vector3.new(0, size.Y / 2 - 0.5, 0), PALETTES.Default, 12, 80)
end

-- Compares each new snapshot with the last one. The first real snapshot only sets the baseline, so joining with
-- rooms and decor you already own never celebrates. init runs before Main.client asks for the server's first
-- snapshot, so ctx.State here is Main's default placeholder, which is skipped.
local function watchSnapshots()
	local initial = ctx.State
	local last: Types.Snapshot? = nil
	ctx.onState(function(snapshot: Types.Snapshot)
		if snapshot == initial or type(snapshot) ~= "table" then
			return
		end
		local previous = last
		last = snapshot
		if not previous then
			return
		end
		if type(snapshot.Rooms) == "table" and type(previous.Rooms) == "table" then
			for roomId, owned in snapshot.Rooms do
				if owned == true and previous.Rooms[roomId] ~= true then
					task.spawn(celebrateRoom, roomId)
				end
			end
		end
		local owned = type(snapshot.Decor) == "table" and snapshot.Decor.Owned
		local ownedBefore = type(previous.Decor) == "table" and previous.Decor.Owned
		if type(owned) == "table" and type(ownedBefore) == "table" then
			for decorId, has in owned do
				if has == true and ownedBefore[decorId] ~= true then
					local wingId = setRewardWing(decorId)
					if wingId then
						task.spawn(celebrateSet, wingId, decorId)
					end
				end
			end
		end
		local placed = type(snapshot.Decor) == "table" and snapshot.Decor.Placed
		local before = type(previous.Decor) == "table" and previous.Decor.Placed
		if type(placed) == "table" and type(before) == "table" then
			for slotKey, decorId in placed do
				if type(decorId) == "string" and before[slotKey] ~= decorId then
					task.spawn(celebrateDecor, slotKey, decorId)
				end
			end
		end
	end)
end

-- A heart left on your sign: a 💖 floats off it.
local function watchHearts()
	local connection: RBXScriptConnection? = nil
	local function bind()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		local plot = myPlot()
		if not plot then
			return
		end
		local hearts = plot:GetAttribute("Hearts")
		local count = if type(hearts) == "number" then hearts else 0
		connection = plot:GetAttributeChangedSignal("Hearts"):Connect(function()
			local value = plot:GetAttribute("Hearts")
			local now = if type(value) == "number" then value else 0
			if now > count and plot:GetAttribute("OwnerUserId") == player.UserId then
				local sign = plot:FindFirstChild("Sign")
				if sign and sign:IsA("BasePart") then
					floaters(sign.Position + Vector3.new(0, sign.Size.Y / 2, 0), { "💖" })
				end
				sound("Heart")
			end
			count = now
		end)
	end
	player:GetAttributeChangedSignal("PlotIndex"):Connect(bind)
	-- Clinics may stream in after we start.
	task.spawn(function()
		local clinics = Workspace:WaitForChild("Clinics", 30)
		if clinics then
			bind()
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Mini-games: a sparkle per good rating over the patient, and the tip flying home
------------------------------------------------------------------------------------------------------------------

local sessionAt: { [number]: Vector3 } = {} -- TreatSession.Session -> above the patient (the last few)
local lastSession: number? = nil

local function onTreatStart(session: any)
	if type(session) ~= "table" or type(session.Session) ~= "number" or typeof(session.Position) ~= "Vector3" then
		return
	end
	sessionAt[session.Session] = session.Position
	lastSession = session.Session
	-- Keep only a handful (one open session per player, so a few is plenty).
	local count = 0
	for _ in sessionAt do
		count += 1
	end
	if count > 6 then
		for id in table.clone(sessionAt) do
			if id ~= lastSession then
				sessionAt[id] = nil
			end
		end
	end
end

local function onRated(_game: any, rating: any)
	local position = if lastSession then sessionAt[lastSession] else nil
	if not position then
		return
	end
	if rating == "Perfect" then
		burst(position + Vector3.new(0, 1, 0), PALETTES.Sparkly, 16, 70)
		floaters(position + Vector3.new(0, 1.5, 0), { "⭐", "✨", "⭐" })
	elseif rating == "Good" then
		burst(position + Vector3.new(0, 1, 0), PALETTES.Default, 7, 55)
	end
end

local function onTreatDone(outcome: any, session: any)
	if type(outcome) ~= "table" then
		return
	end
	local id = if type(session) == "table" and type(session.Session) == "number" then session.Session else nil
	local position = if id then sessionAt[id] else nil
	if not position and type(session) == "table" and typeof(session.Position) == "Vector3" then
		position = session.Position
	end
	local tip = if type(outcome.Tip) == "number" then math.floor(outcome.Tip) else 0
	if position and tip > 0 then
		local lines = { { Text = "💰 +" .. tip, Color = Theme.Colors.Cash } }
		local combo = if type(outcome.Combo) == "number" then math.floor(outcome.Combo) else 0
		if combo >= 2 then
			table.insert(lines, { Text = "🔥 ×" .. combo, Color = Theme.Colors.Primary })
		end
		moneyPop(position + Vector3.new(0, 1, 0), lines)
		task.delay(0.2, Hud.fly, position + Vector3.new(0, 3, 0), "💰", "Cash", Kit.Juice.coins(tip))
	end
	-- An exam revealed the case (TreatOutcome.Case): its icon floats up over the patient with a twinkle (the exam
	-- card says the words, "🩺 It's a cough!").
	local cases = rawget(ctx.Data :: any, "Cases")
	local case = if type(outcome.Case) == "string" and type(cases) == "table" then rawget(cases, outcome.Case) else nil
	if position and type(case) == "table" and type(case.Icon) == "string" then
		floaters(position + Vector3.new(0, 1.5, 0), { case.Icon, "✨" })
	end
	if id and outcome.Complete == true then
		sessionAt[id] = nil
	end
end

local function guarded(name: string, fn: (...any) -> ()): (...any) -> ()
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[CureFX] " .. name .. " failed:", err)
		end
	end
end

function CureFX.init(context: Types.Ctx)
	ctx = context
	ctx.Remotes.Cured.OnClientEvent:Connect(guarded("treated effect", onCured))
	ctx.on("TreatStart", guarded("TreatStart", onTreatStart))
	ctx.on("MiniGameRated", guarded("MiniGameRated", onRated))
	ctx.on("TreatDone", guarded("TreatDone", onTreatDone))
	watchSnapshots()
	watchHearts()
end

return CureFX
