--!strict
-- Builds a nurse Model and moves it (depth-update build plan §B4/§B8). Server only, a library (not in Main's start
-- order); Server/Nurses (plot workers) and Server/NurseBelt (belt riders) use it. OWNER: T3.
--
--   NurseBuilder.build(nurseId): Model
--       The nurse from its Data/Nurses Look (CreatureBuilder.buildLook: Root PrimaryPart at the bottom centre, every
--       other part welded on, CollisionGroup "Patients"), plus a little nurse cap in its rarity's colour with a white
--       cross (so the cap tells the rarity at a glance) and soft sparkles for Epic and up. Under 40 parts. Attributes
--       NurseId, Rarity, Role, Task ("Idle"). Named "Nurse_<NurseId>" (NurseBelt renames riders "Rider_<RiderId>").
--       A Model at ServerStorage.Nurses.<NurseId> (the brother's) replaces the placeholder look: it is cloned,
--       cleaned of scripts and Humanoids, given a Root and welded the same way (no cap is added to it).
--   NurseBuilder.setTask(model, task, icon?)
--       the Task attribute: "Idle" | "Making" | "Healing" | "Cheering" | "Walking" (junk -> "Idle"), and the little
--       bubble over its head: the item it is making (`icon`), 💗 healing, 🎉 cheering, nothing otherwise
--   NurseBuilder.hop(model, from, to, height, seconds, spin?): boolean
--       one hop by the creature-motion contract (build plan §B4): sets HopFrom, HopTo, HopSeconds, HopHeight, HopSpin,
--       HopLean, then HopAt (Workspace:GetServerTimeNow()) last, so a client that listens to HopAt sees the whole hop.
--       Yields `seconds`, then writes Root.CFrame = to ONCE (late joiners and server logic see the right place).
--       False if the model was destroyed meanwhile. The client (Feel/CreatureMotion) draws the arc.
--   NurseBuilder.popIn(model)            a scale-in by the same contract (ScaleFrom/To/At/Seconds/Style/Dir); the
--                                        server scale is already the final one, so nothing else is written
--   NurseBuilder.setGlow(model, on)      a soft PointLight in the rarity's colour (no shadows): Epic+ belt riders
-- Rated Minimal: soft, round and friendly. Every nurse is original (red line 2); names are placeholders.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local NursesData = require(Shared.Data.Nurses)
local Rarities = require(Shared.Data.Rarities)
local CreatureBuilder = require(script.Parent.CreatureBuilder)

local NurseBuilder = {}

NurseBuilder.TASKS = table.freeze({ "Idle", "Making", "Healing", "Cheering", "Walking" })

local COLLISION_GROUP = "Patients"
local MAX_PARTS = 40
local LEAN = 0.12 -- radians forward at the top of a hop (a spin hop doesn't lean)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARKLE_RANK = 3 -- Epic and up sparkle (Data/Rarities.Order index)
local TASK_ICONS: { [string]: string } = { Healing = "💗", Cheering = "🎉" }
local BUBBLE_STUDS = 1.7 -- the task bubble, square
local NEAR_STUDS = 16 -- closer than this the bubble stops growing on screen (like the patients' badges)

local WHITE = Palette.White
local DEFAULT_COLOR = Color3.fromRGB(180, 188, 203)

local rank: { [string]: number } = {}
for index, rarity in Rarities.Order do
	rank[rarity] = index
end

local warnedKit: { [string]: boolean } = {}
local warnedParts: { [string]: boolean } = {}

local function hex(value: any, fallback: Color3): Color3
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return fallback
end

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function nurseOf(nurseId: any): any
	if type(nurseId) ~= "string" then
		return nil
	end
	local nurse = rawget(NursesData :: any, nurseId)
	return if type(nurse) == "table" then nurse else nil
end

local function rarityColor(rarity: string): Color3
	local info = rawget(Rarities :: any, rarity)
	return hex(if type(info) == "table" then info.Color else nil, DEFAULT_COLOR)
end

local function weldTo(root: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CollisionGroup = COLLISION_GROUP
end

------------------------------------------------------------------------------------------------------------------
-- The placeholder: the creature, a nurse cap, sparkles
------------------------------------------------------------------------------------------------------------------

local function capPart(model: Model, root: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weldTo(root, p)
end

-- A small folded nurse cap on the front of the head, in the rarity's colour, with a white cross on its front.
-- The model is still at the origin (CreatureBuilder.buildLook pivots it there), its face looking at -Z.
local function addCap(model: Model, root: BasePart, look: any, color: Color3)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("Body")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local s = model:GetScale()
	local top = head.Position.Y + head.Size.Y / 2
	-- With a hat-like Top (a star, a cloud, a bow...) the cap sits further forward, on the forehead.
	local forward = if type(look) == "table" and look.Top ~= "None" then 0.32 else 0.14
	local z = head.Position.Z - head.Size.Z * forward
	local y = top - (if forward > 0.2 then 0.32 else 0.12) * s
	local cap = CFrame.new(0, y, z) * CFrame.Angles(math.rad(14), 0, 0)
	local size = Vector3.new(1.25, 0.5, 0.78) * s
	capPart(model, root, "NurseCap", size, cap, color)
	local front = cap * CFrame.new(0, 0.02 * s, -size.Z / 2 - 0.01)
	capPart(model, root, "CapCross", Vector3.new(0.13, 0.36, 0.04) * s, front, WHITE)
	capPart(model, root, "CapCross", Vector3.new(0.36, 0.13, 0.04) * s, front, WHITE)
end

local function addSparkles(root: BasePart, rarity: string, color: Color3)
	local level = rank[rarity] or 1
	if level < SPARKLE_RANK then
		return
	end
	local fx = Instance.new("Attachment")
	fx.Name = "RarityFX"
	local _, size = (root.Parent :: Model):GetBoundingBox()
	fx.Position = Vector3.new(0, size.Y * 0.55, 0)
	fx.Parent = root
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "RaritySparkles"
	sparkles.Texture = SPARKLE_TEXTURE
	sparkles.Color = ColorSequence.new(color, WHITE)
	sparkles.LightEmission = 0.6
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.15)
	sparkles.Lifetime = NumberRange.new(0.8, 1.3)
	sparkles.Speed = NumberRange.new(0.6, 1.4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = if level >= 5 then 6 elseif level >= 4 then 4 else 2.5
	sparkles.Shape = Enum.ParticleEmitterShape.Sphere
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.Parent = fx
end

------------------------------------------------------------------------------------------------------------------
-- The brother's model (ServerStorage.Nurses.<NurseId>)
------------------------------------------------------------------------------------------------------------------

local function scrub(model: Instance, nurseId: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Humanoid") then
			if not warnedKit[nurseId] then
				warnedKit[nurseId] = true
				warn("[NurseBuilder] Removed a script or Humanoid from ServerStorage.Nurses." .. nurseId)
			end
			descendant:Destroy()
		elseif descendant:IsA("Highlight") then
			descendant:Destroy() -- the perf budget: at most one Highlight in the world
		elseif descendant:IsA("Light") then
			descendant.Shadows = false -- the perf budget: no shadow-casting lights
		end
	end
end

local function fromKit(nurseId: string, look: any): Model?
	local folder = ServerStorage:FindFirstChild("Nurses")
	local template = folder and folder:FindFirstChild(nurseId)
	if not template then
		return nil
	end
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	elseif template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	else
		if not warnedKit[nurseId] then
			warnedKit[nurseId] = true
			warn("[NurseBuilder] Nurses." .. nurseId .. " must be a Model or a MeshPart; using the placeholder")
		end
		return nil
	end
	scrub(model, nurseId)
	local parts = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			parts += 1
		end
	end
	if parts == 0 then
		model:Destroy()
		return nil
	end
	model:PivotTo(CFrame.identity)
	local _, size = model:GetBoundingBox()
	if size.Y < 1 or size.Y > 9 then -- far off the placeholder size: bring it near 3 studs tall, like patients
		local scale = if type(look) == "table" and type(look.Scale) == "number" then look.Scale else 1
		model:ScaleTo(model:GetScale() * (3 * scale * Config.CreatureSize / math.max(size.Y, 0.05)))
	end

	-- Root at the bottom centre, everything welded to it: one CFrame moves the whole nurse.
	model:PivotTo(CFrame.identity)
	local box, boxSize = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.CFrame = CFrame.new(box.X, box.Y - boxSize.Y / 2, box.Z)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Massless = true
	root.CollisionGroup = COLLISION_GROUP
	root.Parent = model
	model.PrimaryPart = root
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			weldTo(root, descendant)
		end
	end
	model:PivotTo(CFrame.identity)
	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, boxSize.Y + 0.25, 0)
	anchor.Parent = root
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function NurseBuilder.build(nurseId: string): Model
	local nurse = nurseOf(nurseId)
	local look = if nurse then nurse.Look else nil
	local rarity: string = if nurse then nurse.Rarity else "Common"
	local color = rarityColor(rarity)

	local model = fromKit(nurseId, look)
	if not model then
		model = CreatureBuilder.buildLook(look, "Nurse_" .. tostring(nurseId))
		local root = model.PrimaryPart
		if root then
			addCap(model, root, look, color)
		end
	end
	local root = model.PrimaryPart
	if root then
		addSparkles(root, rarity, color)
	end

	local parts = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	if parts > MAX_PARTS and not warnedParts[nurseId] then
		warnedParts[nurseId] = true
		warn(("[NurseBuilder] %s has %d parts (budget %d)"):format(tostring(nurseId), parts, MAX_PARTS))
	end

	model.Name = "Nurse_" .. tostring(nurseId)
	model:SetAttribute("NurseId", nurseId)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Role", if nurse then nurse.Role else "Maker")
	model:SetAttribute("Task", "Idle")
	return model
end

-- The little bubble over a working nurse's head (made on first use).
local function bubble(model: Model): TextLabel?
	local root = model.PrimaryPart
	local anchor = root and root:FindFirstChild("IconAnchor")
	if not anchor then
		return nil
	end
	local gui = anchor:FindFirstChild("TaskGui")
	if gui and gui:IsA("BillboardGui") then
		local label = gui:FindFirstChild("Icon", true)
		return if label and label:IsA("TextLabel") then label else nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TaskGui"
	billboard.Size = UDim2.fromScale(BUBBLE_STUDS, BUBBLE_STUDS)
	billboard.StudsOffset = Vector3.new(0, BUBBLE_STUDS * 0.6, 0)
	billboard.DistanceLowerLimit = NEAR_STUDS
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Enabled = false
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = WHITE
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	Palette.outlineShape(disc, 2)
	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.78, 0.78)
	label.Position = UDim2.fromScale(0.11, 0.11)
	label.TextScaled = true
	label.Font = Palette.BodyFont
	label.Text = ""
	label.Parent = disc
	disc.Parent = billboard
	billboard.Parent = anchor
	return label
end

function NurseBuilder.setTask(model: Model, task: string, icon: string?)
	local name = if table.find(NurseBuilder.TASKS, task) then task else "Idle"
	if model:GetAttribute("Task") ~= name then
		model:SetAttribute("Task", name)
	end
	local show = if type(icon) == "string" and icon ~= "" then icon else TASK_ICONS[name]
	local root = model.PrimaryPart
	local anchor = root and root:FindFirstChild("IconAnchor")
	local existing = anchor and anchor:FindFirstChild("TaskGui")
	if not show and not existing then
		return -- nothing to show and no bubble yet: don't make one
	end
	local label = bubble(model)
	if not label then
		return
	end
	local gui = label:FindFirstAncestorWhichIsA("BillboardGui")
	if show and label.Text ~= show then
		label.Text = show
	end
	if gui and gui.Enabled ~= (show ~= nil) then
		gui.Enabled = show ~= nil
	end
end

function NurseBuilder.hop(
	model: Model,
	from: CFrame,
	to: CFrame,
	height: number,
	seconds: number,
	spin: number?
): boolean
	local root = model.PrimaryPart
	if not root or not model.Parent then
		return false
	end
	local s = math.max(seconds, 0.12)
	model:SetAttribute("HopFrom", from)
	model:SetAttribute("HopTo", to)
	model:SetAttribute("HopSeconds", s)
	model:SetAttribute("HopHeight", height)
	model:SetAttribute("HopSpin", spin or 0)
	model:SetAttribute("HopLean", if spin then 0 else LEAN)
	model:SetAttribute("HopAt", Workspace:GetServerTimeNow())
	task.wait(s)
	if not model.Parent or model.PrimaryPart ~= root then
		return false
	end
	root.CFrame = to
	return true
end

function NurseBuilder.popIn(model: Model)
	local scale = model:GetScale()
	model:SetAttribute("ScaleFrom", scale * 0.05)
	model:SetAttribute("ScaleTo", scale)
	model:SetAttribute("ScaleSeconds", 0.4)
	model:SetAttribute("ScaleStyle", "Back")
	model:SetAttribute("ScaleDir", "Out")
	model:SetAttribute("ScaleAt", Workspace:GetServerTimeNow())
end

function NurseBuilder.setGlow(model: Model, on: boolean)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local holder: Instance = root:FindFirstChild("RarityFX") or root
	local light = holder:FindFirstChild("RarityGlow")
	if not on then
		if light then
			light:Destroy()
		end
		return
	end
	if light then
		return
	end
	local glow = Instance.new("PointLight")
	glow.Name = "RarityGlow"
	glow.Color = rarityColor(tostring(model:GetAttribute("Rarity")))
	glow.Brightness = 1.4
	glow.Range = 9
	glow.Shadows = false -- the perf budget: no shadow-casting lights
	glow.Parent = holder
end

return NurseBuilder
