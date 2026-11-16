--!strict
-- Builds a nurse Model and moves it (depth-update build plan §B4/§B8; Progression v2 build plan §B4 and §C T1).
-- Server only, a library (not in Main's start order); Server/Nurses (plot workers), Server/Abilities (the ring) and
-- Server/NurseBelt (belt riders) use it. OWNER: T1 (Progression v2).
--
--   NurseBuilder.build(nurseId): Model
--       The nurse from its Data/Nurses Look, built like a patient (CreatureBuilder.buildLook: the blocky body and
--       rig, memory-20261117-004; Root PrimaryPart at the bottom centre, Core on Root.PoseJoint with every part
--       welded to it, the limbs on their Motor6Ds, the sockets, CollisionGroup "Patients"; a happy face), plus a
--       block nurse cap on the front of its head in its rarity's colour (brought to a world value), with a
--       warm-white brim and our paw-heart on its front, never a cross (welded to Core, so it follows the body; the
--       cap tells the rarity at a glance), and soft sparkles for Epic and up. The task bubble, job hat and ability
--       ring hang on Root.IconAnchor, kept clear over the head and cap. Under 40 parts. Attributes NurseId, Rarity,
--       Role, Task ("Idle"). Named "Nurse_<NurseId>" (NurseBelt renames riders "Rider_<RiderId>"). A Model at
--       ServerStorage.Nurses.<NurseId> (the brother's) replaces the placeholder look: it is cloned, cleaned of
--       scripts and Humanoids, and given the same Root, Core and PoseJoint (CreatureBuilder.rigKit; no cap is added
--       to it).
--   NurseBuilder.setTask(model, task, icon?)
--       the Task attribute: "Idle" | "Making" | "Healing" | "Cheering" | "Walking" | "Escorting" | "Greeting" |
--       "Treating" (junk -> "Idle"), and the little bubble over its head: the item it is making (`icon`), 💗 healing or
--       treating, 🎉 cheering, 👋 greeting, 🛏️ escorting, nothing otherwise
--   NurseBuilder.setJob(model, jobId)    the Job attribute and the job hat: a small chip with the job's Data/Jobs icon
--                                        on the task bubble's corner (alone over the head while there's no bubble)
--   NurseBuilder.addAbility(model, abilityId)
--       the Ability attribute, and the ability ring: a small BillboardGui "AbilityRing" under Root.IconAnchor, beside
--       the bubble (only within 40 studs): Ring (a white disc with a Track UIStroke in the rarity colour, its Fill disc
--       growing as the cooldown ends, the ability's Icon on top). No parts. A client may draw a smoother ring inside it
--       (T8 Feel/HospitalFX adds "RingFX"); the sparkle when it fires is the client's too (AbilityAt), so reduced
--       motion stays each client's call
--   NurseBuilder.setAbility(model, fraction)   the Fill: 0 = just fired .. 1 = ready, solid (no numbers, ever).
--                                        Server/Abilities moves it in a few steps per cooldown, never every frame
--   NurseBuilder.hop(model, from, to, height, seconds, spin?): boolean
--       one hop by the creature-motion contract (build plan §B4): sets HopFrom, HopTo, HopSeconds, HopHeight, HopSpin,
--       HopLean, then HopAt (Workspace:GetServerTimeNow()) last, so a client that listens to HopAt sees the whole hop.
--       Yields `seconds`, then writes Root.CFrame = to ONCE (late joiners and server logic see the right place).
--       False if the model was destroyed meanwhile. The client (Feel/CreatureMotion) draws the arc.
--   NurseBuilder.popIn(model)            a scale-in by the same contract (ScaleFrom/To/At/Seconds/Style/Dir); the
--                                        server scale is already the final one, so nothing else is written
--   NurseBuilder.setGlow(model, on)      a soft PointLight in the rarity's colour (no shadows): Epic+ belt riders
-- Rated Minimal: chunky and friendly. Every nurse is original (red line 2); names are placeholders. No cross on any
-- nurse (the build plan's Global constraints): the cap carries World/Parts' paw-heart.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local AbilitiesData = require(Shared.Data.Abilities)
local JobsData = require(Shared.Data.Jobs)
local NursesData = require(Shared.Data.Nurses)
local Rarities = require(Shared.Data.Rarities)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Parts = require(script.Parent.World.Parts)

local NurseBuilder = {}

NurseBuilder.TASKS =
	table.freeze({ "Idle", "Making", "Healing", "Cheering", "Walking", "Escorting", "Greeting", "Treating" })

local COLLISION_GROUP = "Patients"
local MAX_PARTS = 40 -- every nurse stays under it, the cap included
local LEAN = 0.12 -- radians forward at the top of a hop (a spin hop doesn't lean)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARKLE_RANK = 3 -- Epic and up sparkle (Data/Rarities.Order index)
local TASK_ICONS: { [string]: string } =
	{ Healing = "💗", Cheering = "🎉", Greeting = "👋", Treating = "💗", Escorting = "🛏️" }
local BUBBLE_STUDS = 1.7 -- the task bubble, square
local HAT_SCALE = 0.5 -- the job hat chip, of the bubble's size
local RING_STUDS = 1.25 -- the ability ring, square
local RING_DISTANCE = 40 -- studs: the ring only shows this close (§C T1)
local RING_NAME = "AbilityRing" -- T8 Feel/HospitalFX finds it by this name and draws its smooth ring inside
local NEAR_STUDS = 16 -- closer than this the bubble stops growing on screen (like the patients' badges)

local WHITE = Palette.White
local DEFAULT_COLOR = Color3.fromRGB(180, 188, 203)
local CAP_BRIM = Color3.fromHex(CreatureBuilder.Pure.WARM_WHITE) -- warm white: no pure white on the world
local CAP_HEART = Palette.Accent.Pink -- the paw-heart's heart (never red-and-white, never a cross)
local CAP_NEAR = 60 -- studs: the paw-heart drawing hides past this

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

-- The cap's colour: the rarity's hue at a world value (a lit part, so not the UI's full-bright colour).
local function capColor(rarity: string): Color3
	local info = rawget(Rarities :: any, rarity)
	local color = if type(info) == "table" then info.Color else nil
	return hex(if type(color) == "string" then CreatureBuilder.Pure.mid(color) else nil, DEFAULT_COLOR)
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

local function capPart(model: Model, root: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local core = model:FindFirstChild("Core")
	local body = if core and core:IsA("BasePart") then core else root
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weldTo(body, p)
	return p
end

-- A block nurse cap on the head's top front edge (just behind the face), in the rarity's colour: a warm-white brim
-- round its foot and our paw-heart on its front (never a cross). The model is still at the origin
-- (CreatureBuilder.buildLook pivots it there), its face looking at -Z. Welded to Core (the rig's body), so it leans
-- and bobs with the head. It sits on the stud plate when there is one (`StudTop`), in front of any Top (a star, a
-- cloud, a bow), which stand in the head's middle.
local function addCap(model: Model, root: BasePart, color: Color3)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("Body")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local s = model:GetScale()
	local top = head.Position.Y + head.Size.Y / 2
	local plate = model:FindFirstChild("StudTop")
	if plate and plate:IsA("BasePart") then
		top = math.max(top, plate.Position.Y + plate.Size.Y / 2)
	end
	local front = head.Position.Z - head.Size.Z / 2
	local size = Vector3.new(math.min(1.3 * s, head.Size.X * 0.6), 0.56 * s, 0.7 * s)
	local z = front + size.Z / 2 + 0.08 * s -- set back a little, so the brim never shares the face's front plane
	local cap = capPart(model, root, "NurseCap", size, CFrame.new(0, top + size.Y / 2 - 0.04 * s, z), color)
	local brim = Vector3.new(size.X + 0.08 * s, 0.14 * s, size.Z + 0.08 * s)
	capPart(model, root, "CapBrim", brim, CFrame.new(0, top + brim.Y / 2 - 0.04 * s, z), CAP_BRIM)

	-- The paw-heart on the cap's front, above the brim.
	local gui = Parts.surface(cap, "CapGui", Enum.NormalId.Front, 100, CAP_NEAR, 0.4)
	local holder = Instance.new("Frame")
	holder.Name = "Mark"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 0.74)
	holder.Parent = gui
	Parts.pawHeart(holder, UDim2.fromScale(0.86, 0.86), CAP_HEART)

	-- The task bubble, the job hat and the ability ring hang on IconAnchor: keep it clear over the cap.
	local anchor = root:FindFirstChild("IconAnchor")
	if anchor and anchor:IsA("Attachment") then
		local capTop = root.CFrame:PointToObjectSpace(cap.Position).Y + size.Y / 2
		if anchor.Position.Y < capTop + 0.25 then
			anchor.Position = Vector3.new(0, capTop + 0.25, 0)
		end
	end
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

	-- The patients' rig: Root at the bottom centre, Core on Root.PoseJoint, every part welded to Core. One CFrame
	-- (Root's) still moves the whole nurse.
	model.Name = "Nurses." .. nurseId
	return CreatureBuilder.rigKit(model)
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
			addCap(model, root, capColor(rarity))
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
	if parts >= MAX_PARTS and not warnedParts[nurseId] then
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

local function anchorOf(model: Model): Instance?
	local root = model.PrimaryPart
	return root and root:FindFirstChild("IconAnchor")
end

local function round(frame: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
end

local function iconLabel(parent: Instance, scale: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(scale, scale)
	label.TextScaled = true
	label.Font = Palette.BodyFont
	label.Text = ""
	label.ZIndex = 3
	label.Parent = parent
	return label
end

-- The task bubble over a working nurse's head (made on first use): a Disc with the task's icon and, on its corner, the
-- Hat chip with the job's icon.
local function taskGui(model: Model): BillboardGui?
	local anchor = anchorOf(model)
	if not anchor then
		return nil
	end
	local existing = anchor:FindFirstChild("TaskGui")
	if existing and existing:IsA("BillboardGui") then
		return existing
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
	disc.Visible = false
	round(disc)
	Palette.outlineShape(disc, 2)
	iconLabel(disc, 0.78)
	disc.Parent = billboard
	local hat = Instance.new("Frame")
	hat.Name = "Hat"
	hat.Size = UDim2.fromScale(HAT_SCALE, HAT_SCALE)
	hat.BackgroundColor3 = WHITE
	hat.Visible = false
	hat.ZIndex = 2
	round(hat)
	Palette.outlineShape(hat, 2)
	iconLabel(hat, 0.8)
	hat.Parent = billboard
	billboard.Parent = anchor
	return billboard
end

-- The hat sits on the disc's top-left corner, or in the middle on its own; the billboard shows while either does.
local function layoutBubble(gui: BillboardGui)
	local disc = gui:FindFirstChild("Disc")
	local hat = gui:FindFirstChild("Hat")
	local discOn = disc ~= nil and disc:IsA("GuiObject") and disc.Visible
	local hatOn = hat ~= nil and hat:IsA("GuiObject") and hat.Visible
	if hat and hat:IsA("GuiObject") then
		local anchor = if discOn then Vector2.new(0.2, 0.2) else Vector2.new(0.5, 0.5)
		local position = if discOn then UDim2.fromScale(0, 0) else UDim2.fromScale(0.5, 0.75)
		if hat.AnchorPoint ~= anchor then
			hat.AnchorPoint = anchor
		end
		if hat.Position ~= position then
			hat.Position = position
		end
	end
	local on = discOn or hatOn
	if gui.Enabled ~= on then
		gui.Enabled = on
	end
end

local function setIcon(frame: Instance?, text: string?)
	if not frame or not frame:IsA("GuiObject") then
		return
	end
	local label = frame:FindFirstChild("Icon")
	local show = type(text) == "string" and text ~= ""
	if show and label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text :: string
	end
	if frame.Visible ~= show then
		frame.Visible = show
	end
end

function NurseBuilder.setTask(model: Model, task: string, icon: string?)
	local name = if table.find(NurseBuilder.TASKS, task) then task else "Idle"
	if model:GetAttribute("Task") ~= name then
		model:SetAttribute("Task", name)
	end
	local show = if type(icon) == "string" and icon ~= "" then icon else TASK_ICONS[name]
	local anchor = anchorOf(model)
	local existing = anchor and anchor:FindFirstChild("TaskGui")
	if not show and not existing then
		return -- nothing to show and no bubble yet: don't make one
	end
	local gui = taskGui(model)
	if not gui then
		return
	end
	setIcon(gui:FindFirstChild("Disc"), show)
	layoutBubble(gui)
end

function NurseBuilder.setJob(model: Model, jobId: string)
	local job = if type(jobId) == "string" then rawget(JobsData :: any, jobId) else nil
	local id = if type(job) == "table" then jobId else ""
	if model:GetAttribute("Job") ~= id then
		model:SetAttribute("Job", id)
	end
	local gui = taskGui(model)
	if not gui then
		return
	end
	setIcon(gui:FindFirstChild("Hat"), if type(job) == "table" then job.Icon else nil)
	layoutBubble(gui)
end

function NurseBuilder.addAbility(model: Model, abilityId: string)
	local ability = if type(abilityId) == "string" then rawget(AbilitiesData :: any, abilityId) else nil
	if type(ability) ~= "table" then
		return
	end
	model:SetAttribute("Ability", abilityId)
	local anchor = anchorOf(model)
	if not anchor or anchor:FindFirstChild(RING_NAME) then
		return
	end
	local color = rarityColor(tostring(model:GetAttribute("Rarity")))

	local billboard = Instance.new("BillboardGui")
	billboard.Name = RING_NAME
	billboard.Size = UDim2.fromScale(RING_STUDS, RING_STUDS)
	billboard.StudsOffset = Vector3.new(BUBBLE_STUDS * 0.95, BUBBLE_STUDS * 0.45, 0)
	billboard.DistanceLowerLimit = NEAR_STUDS
	billboard.MaxDistance = RING_DISTANCE
	billboard.LightInfluence = 0
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = WHITE
	ring.BackgroundTransparency = 0.1
	round(ring)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Track"
	stroke.Color = color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	round(fill)
	fill.Parent = ring
	local label = iconLabel(ring, 0.72)
	label.Text = ability.Icon
	ring.Parent = billboard
	billboard.Parent = anchor
end

function NurseBuilder.setAbility(model: Model, fraction: number)
	local anchor = anchorOf(model)
	local gui = anchor and anchor:FindFirstChild(RING_NAME)
	local ring = gui and gui:FindFirstChild("Ring")
	local fill = ring and ring:FindFirstChild("Fill")
	if not fill or not fill:IsA("Frame") then
		return
	end
	local f = if type(fraction) == "number" and fraction == fraction then math.clamp(fraction, 0, 1) else 0
	local size = UDim2.fromScale(f, f)
	if fill.Size ~= size then
		fill.Size = size
	end
	local transparency = if f >= 1 then 0 else 0.45 -- full and solid: ready
	if fill.BackgroundTransparency ~= transparency then
		fill.BackgroundTransparency = transparency
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
