--!strict
-- Creature motion on the client (depth-update design §5, build plan §B4 "creature motion contract"). OWNER: T7.
--   CreatureMotion.init(ctx)   draws every Model tagged `CreatureMotion` (patients, nurses on plots), locally
--   CreatureMotion.Motion      the timing maths below (pure; a scratch Lune harness loads that block on its own)
--
-- Why: the server used to write every moving creature's Root.CFrame on every Heartbeat, so a 0.3 s hop sent about
-- 18 CFrames to every player. Now the server sets one set of attributes per animation, waits, and writes the end
-- pose once (Root.CFrame = HopTo, then the final ScaleTo), so late joiners and the server's own checks still see the
-- right place. This module draws the in-between on RenderStepped, and only while something moves: with nothing
-- moving, its RenderStepped connection is disconnected (it sleeps).
--
-- The attributes (the server sets each group together, its time last: a new time means a new animation):
--   Hop     HopFrom, HopTo (CFrame), HopSeconds, HopHeight, HopSpin, HopLean (radians), HopAt (server time)
--   Shake   ShakeAt (server time): a 0.55 s "no, not that" head-shake
--   Tilt    Tilt (radians): a sad droop over everything else, until it's set back to 0
--   Scale   ScaleFrom, ScaleTo, ScaleSeconds, ScaleStyle ("Back"|"Sine"|"Quad"), ScaleDir ("In"|"Out"), ScaleAt
-- The server helpers that set them: CreatureBuilder.hop / .shake / .tilt / .scale.
--
-- Timing: each animation plays from its server time plus a small smoothed delay (how late attributes reach this
-- client, at most Motion.MAX_DELAY), so a chain of hops plays whole and back to back instead of skipping the start
-- of each hop. A hop that arrives while the one before is still playing waits its turn. A creature further than
-- CULL_STUDS from the camera jumps to each animation's end instead of being drawn in between. A pose the server sets
-- without a hop (a teleport) is noticed and kept.
-- Reduced motion (Kit.reducedMotion(): the device setting or the ✨/💤 switch): lower hops with no lean or spin, a
-- small shake, no overshoot when growing or shrinking. The same timings, so nothing gets out of step.
-- Nurses' rarity sparkles (NurseBuilder's RaritySparkles, made on the server and always on) follow THIS client's
-- reduced motion too: off while Kit.reducedMotion(), on otherwise (UI/BeltView does the same for belt riders). No
-- loop: it reacts to a nurse appearing, an emitter streaming in, and the setting changing.
-- Nothing here is game logic: the server decides where every creature is.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Kit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Kit"))

local CreatureMotion = {}

-- BEGIN PURE: maths only (no services, no requires, no globals but math); a scratch Lune harness loads this block.
local Motion = {}
Motion.SHAKE_SECONDS = 0.55
Motion.SHAKE_ANGLE = 0.42 -- radians at the start of a shake, easing out to 0
Motion.SHAKE_TURNS = 3 -- side-to-side wiggles in one shake
Motion.CALM_HEIGHT = 0.35 -- reduced motion: hops are this much as high
Motion.CALM_SHAKE = 0.35 -- and shakes this much as wide
Motion.MAX_DELAY = 0.25 -- seconds: the most the drawing runs behind the server's clock
Motion.DELAY_BLEND = 0.2 -- how fast the delay follows each new sample
Motion.STALE_SECONDS = 1 -- a sample older than this is a late joiner seeing an old hop, not network delay
Motion.MIN_SCALE = 0.02
Motion.SAME_STUDS = 0.01 -- two poses closer than this, and turned alike, are the same pose
Motion.SAME_DOT = 0.9999

-- A finite number, else the fallback (attributes are only trusted after this).
function Motion.number(value: any, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return fallback
end

-- How far through an animation is at `now`: (0..1, done). Before it starts: 0. No length: done at once.
function Motion.progress(at: number, seconds: number, now: number): (number, boolean)
	if seconds <= 0 then
		return 1, true
	end
	local t = (now - at) / seconds
	if t >= 1 then
		return 1, true
	end
	return math.max(t, 0), false
end

-- The bob of a hop: 0 -> 1 -> 0.
function Motion.arc(t: number): number
	return 4 * t * (1 - t)
end

-- A hop's shape at t (`eased` = the eased t): (lift studs, lean radians, spin radians).
function Motion.hopShape(
	t: number,
	eased: number,
	height: number,
	lean: number,
	spin: number,
	calm: boolean
): (number, number, number)
	local arc = Motion.arc(t)
	if calm then
		return height * Motion.CALM_HEIGHT * arc, 0, 0
	end
	return height * arc, -lean * arc, spin * eased
end

-- The head-shake's turn (radians) at t.
function Motion.shakeAngle(t: number, calm: boolean): number
	local amplitude = Motion.SHAKE_ANGLE * (if calm then Motion.CALM_SHAKE else 1)
	return math.sin(t * math.pi * 2 * Motion.SHAKE_TURNS) * amplitude * (1 - t)
end

function Motion.scaleValue(from: number, to: number, eased: number): number
	return math.max(from + (to - from) * eased, Motion.MIN_SCALE)
end

-- The easing style to draw with: "Back" | "Sine" | "Quad" (junk -> "Quad"; reduced motion: no Back overshoot).
function Motion.styleName(name: any, calm: boolean): string
	if name ~= "Back" and name ~= "Sine" and name ~= "Quad" then
		return "Quad"
	end
	if calm and name == "Back" then
		return "Quad"
	end
	return name
end

-- "In" | "Out" | "InOut" (junk -> "Out").
function Motion.directionName(name: any): string
	if name == "In" or name == "InOut" then
		return name
	end
	return "Out"
end

-- Blends one sample (server now - an animation's server time, when its attributes arrive) into the delay.
-- A stale or impossible sample leaves it as it was.
function Motion.blendDelay(current: number?, sample: number): number?
	if sample ~= sample or sample < -0.05 or sample > Motion.STALE_SECONDS then
		return current
	end
	local clamped = math.clamp(sample, 0, Motion.MAX_DELAY)
	if current == nil then
		return clamped
	end
	return current + (clamped - current) * Motion.DELAY_BLEND
end

-- Two CFrames are the same pose: close, and turned the same way (a replicated value is never bit-for-bit ours).
function Motion.same(a: CFrame, b: CFrame): boolean
	if (a.Position - b.Position).Magnitude > Motion.SAME_STUDS then
		return false
	end
	return a.LookVector:Dot(b.LookVector) >= Motion.SAME_DOT and a.UpVector:Dot(b.UpVector) >= Motion.SAME_DOT
end
-- END PURE

CreatureMotion.Motion = Motion

local TAG = "CreatureMotion"
local CULL_STUDS = 160 -- further from the camera than this, a creature jumps to the end of each animation

-- Attributes that change what's drawn. The times also say how late attributes reach this client.
local WATCHED: { [string]: boolean } = {
	HopFrom = true,
	HopTo = true,
	HopAt = true,
	HopSeconds = true,
	HopHeight = true,
	HopSpin = true,
	HopLean = true,
	ShakeAt = true,
	Tilt = true,
	ScaleFrom = true,
	ScaleTo = true,
	ScaleAt = true,
	ScaleSeconds = true,
	ScaleStyle = true,
	ScaleDir = true,
}
local TIMES: { [string]: boolean } = { HopAt = true, ShakeAt = true, ScaleAt = true }

local STYLES: { [string]: Enum.EasingStyle } = {
	Back = Enum.EasingStyle.Back,
	Sine = Enum.EasingStyle.Sine,
	Quad = Enum.EasingStyle.Quad,
}
local DIRECTIONS: { [string]: Enum.EasingDirection } = {
	In = Enum.EasingDirection.In,
	Out = Enum.EasingDirection.Out,
	InOut = Enum.EasingDirection.InOut,
}

type Hop = { From: CFrame, To: CFrame, At: number, Seconds: number, Height: number, Spin: number, Lean: number }
type Scale = { From: number, To: number, At: number, Seconds: number, Style: string, Direction: string }
type Entry = {
	Model: Model,
	Dirty: boolean, -- attributes changed: read them before drawing
	Hop: Hop?, -- the hop being drawn
	NextHop: Hop?, -- one that arrived while Hop was still playing: it waits its turn
	HopSeen: number?, -- the HopAt last read (a new value = a new hop)
	ShakeAt: number?,
	ShakeSeen: number?,
	Tilt: number,
	Scale: Scale?,
	ScaleSeen: number?,
	Rest: CFrame?, -- the pose under the overlays while no hop plays
	Written: CFrame?, -- the pose this client last drew (nil = never drawn)
	Land: boolean, -- draw once even with nothing playing (a new tilt, a hop that ended before we saw it)
	Changed: RBXScriptConnection,
	Moved: RBXScriptConnection?, -- only while tilted: the server's end pose would wipe the droop
}

local tracked: { [Model]: Entry } = {}
local active: { [Model]: Entry } = {} -- drawn every frame until they rest
local pending: { [Model]: Entry } = {} -- woken while a frame was being drawn
local stepping = false
local connection: RBXScriptConnection? = nil
local lag: number? = nil -- seconds the drawing runs behind the server clock (smoothed)
local failures = 0

local step: () -> () -- defined below

local function wake(entry: Entry)
	if stepping then
		pending[entry.Model] = entry
		return
	end
	active[entry.Model] = entry
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

local function sample(value: any)
	if type(value) == "number" then
		lag = Motion.blendDelay(lag, Workspace:GetServerTimeNow() - value)
	end
end

local function watchTilt(entry: Entry)
	local root = entry.Model.PrimaryPart
	if entry.Tilt ~= 0 and root and not entry.Moved then
		entry.Moved = root:GetPropertyChangedSignal("CFrame"):Connect(function()
			local written = entry.Written
			if written and not Motion.same(root.CFrame, written) then
				entry.Land = true -- the server set its end pose: put the droop back on it
				wake(entry)
			end
		end)
	elseif entry.Tilt == 0 then
		local moved = entry.Moved
		entry.Moved = nil
		if moved then
			moved:Disconnect()
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Reading the attributes
------------------------------------------------------------------------------------------------------------------

local function readHop(entry: Entry, now: number)
	local model = entry.Model
	local at = model:GetAttribute("HopAt")
	local to = model:GetAttribute("HopTo")
	if type(at) ~= "number" or at == entry.HopSeen or typeof(to) ~= "CFrame" then
		return
	end
	entry.HopSeen = at
	local from = model:GetAttribute("HopFrom")
	local hop: Hop = {
		From = if typeof(from) == "CFrame" then from else to,
		To = to,
		At = at,
		Seconds = math.max(Motion.number(model:GetAttribute("HopSeconds"), 0), 0),
		Height = Motion.number(model:GetAttribute("HopHeight"), 0),
		Spin = Motion.number(model:GetAttribute("HopSpin"), 0),
		Lean = Motion.number(model:GetAttribute("HopLean"), 0),
	}
	local _, done = Motion.progress(hop.At, hop.Seconds, now)
	if done then
		-- It ended before we saw it (a hitch, or a snap with HopSeconds 0): land where it ends if we've drawn this
		-- creature before. One that just streamed in is already where the server put it.
		entry.Hop, entry.NextHop = nil, nil
		if entry.Written then
			entry.Rest = hop.To
			entry.Land = true
		end
		return
	end
	local current = entry.Hop
	if current and hop.At > now then
		local _, currentDone = Motion.progress(current.At, current.Seconds, now)
		if not currentDone then
			entry.NextHop = hop
			return
		end
	end
	entry.Hop, entry.NextHop = hop, nil
end

local function readScale(entry: Entry, now: number)
	local model = entry.Model
	local at = model:GetAttribute("ScaleAt")
	local to = model:GetAttribute("ScaleTo")
	if type(at) ~= "number" or at == entry.ScaleSeen or type(to) ~= "number" then
		return
	end
	entry.ScaleSeen = at
	local target = math.max(Motion.number(to, 1), Motion.MIN_SCALE)
	local scale: Scale = {
		From = math.max(Motion.number(model:GetAttribute("ScaleFrom"), target), Motion.MIN_SCALE),
		To = target,
		At = at,
		Seconds = math.max(Motion.number(model:GetAttribute("ScaleSeconds"), 0), 0),
		Style = tostring(model:GetAttribute("ScaleStyle")),
		Direction = tostring(model:GetAttribute("ScaleDir")),
	}
	local _, done = Motion.progress(scale.At, scale.Seconds, now)
	-- Already over: the server's own end scale is (or soon will be) here.
	entry.Scale = if done then nil else scale
end

local function read(entry: Entry, now: number)
	entry.Dirty = false
	local model = entry.Model
	readHop(entry, now)
	local shakeAt = model:GetAttribute("ShakeAt")
	if type(shakeAt) == "number" and shakeAt ~= entry.ShakeSeen then
		entry.ShakeSeen = shakeAt
		local _, done = Motion.progress(shakeAt, Motion.SHAKE_SECONDS, now)
		entry.ShakeAt = if done then nil else shakeAt
	end
	local tilt = Motion.number(model:GetAttribute("Tilt"), 0)
	if tilt ~= entry.Tilt then
		entry.Tilt = tilt
		entry.Land = true
		watchTilt(entry)
	end
	readScale(entry, now)
end

------------------------------------------------------------------------------------------------------------------
-- Drawing one creature. Returns true while something still plays.
------------------------------------------------------------------------------------------------------------------

local function render(entry: Entry, now: number, calm: boolean, eye: Vector3): boolean
	local model = entry.Model
	local root = model.PrimaryPart
	if not root then
		return false
	end
	if entry.Dirty then
		read(entry, now)
	end
	local far = (root.Position - eye).Magnitude > CULL_STUDS
	local busy = false
	local land = entry.Land
	entry.Land = false

	local pose: CFrame? = nil
	local landed = false -- a hop ended in this frame: its end is the rest pose
	local hop = entry.Hop
	while hop do -- a finished hop hands over to the one waiting behind it
		local t, done = Motion.progress(hop.At, hop.Seconds, now)
		if done or far then
			entry.Rest = hop.To
			landed, land = true, true
			hop = entry.NextHop
			entry.Hop, entry.NextHop = hop, nil
		else
			busy = true
			local eased = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local lift, lean, spin = Motion.hopShape(t, eased, hop.Height, hop.Lean, hop.Spin, calm)
			pose = hop.From:Lerp(hop.To, eased) * CFrame.new(0, lift, 0) * CFrame.Angles(lean, spin, 0)
			break
		end
	end
	if not pose then
		local written = entry.Written
		if not landed and (not written or not Motion.same(root.CFrame, written)) then
			-- Never drawn here, or the server moved it since we last drew it (an end pose, a teleport): keep that.
			entry.Rest = root.CFrame
		end
		pose = entry.Rest or root.CFrame
	end
	local drawn = pose :: CFrame

	local shakeAt = entry.ShakeAt
	if shakeAt then
		local t, done = Motion.progress(shakeAt, Motion.SHAKE_SECONDS, now)
		if done or far then
			entry.ShakeAt = nil
			land = true
		else
			busy = true
			drawn *= CFrame.Angles(0, Motion.shakeAngle(t, calm), 0)
		end
	end
	if entry.Tilt ~= 0 then
		drawn *= CFrame.Angles(entry.Tilt, 0, 0)
	end

	local scale = entry.Scale
	if scale then
		local t, done = Motion.progress(scale.At, scale.Seconds, now)
		local value = scale.To
		if done or far then
			entry.Scale = nil
		else
			busy = true
			local style = STYLES[Motion.styleName(scale.Style, calm)]
			local direction = DIRECTIONS[Motion.directionName(scale.Direction)]
			value = Motion.scaleValue(scale.From, scale.To, TweenService:GetValue(t, style, direction))
		end
		-- Scale first: it scales round the pivot (Root), so Root itself stays where it is. The end is exact.
		if model:GetScale() ~= value then
			model:ScaleTo(value)
		end
	end

	if busy or land then
		entry.Written = drawn -- before the write: a tilt watcher sees its own write as ours
		if root.CFrame ~= drawn then
			root.CFrame = drawn
		end
	end
	return busy
end

step = function()
	debug.profilebegin("CreatureMotion")
	stepping = true
	local now = Workspace:GetServerTimeNow() - (lag or 0)
	local calm = Kit.reducedMotion()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for model, entry in active do
		if tracked[model] ~= entry then
			active[model] = nil
			continue
		end
		local ok, result = pcall(render, entry, now, calm, eye)
		if not ok then
			failures += 1
			if failures <= 3 then
				warn("[CreatureMotion] " .. tostring(result))
			end
			active[model] = nil
		elseif not result then
			active[model] = nil
		end
	end
	stepping = false
	for model, entry in pending do
		active[model] = entry
	end
	table.clear(pending)
	if next(active) == nil then
		local current = connection
		connection = nil
		if current then
			current:Disconnect() -- nothing moves: sleep until an attribute changes
		end
	end
	debug.profileend()
end

------------------------------------------------------------------------------------------------------------------
-- Which creatures to draw
------------------------------------------------------------------------------------------------------------------

local function untrack(instance: Instance)
	local model = instance :: Model
	local entry = tracked[model]
	if not entry then
		return
	end
	tracked[model] = nil
	active[model] = nil
	pending[model] = nil
	entry.Changed:Disconnect()
	local moved = entry.Moved
	if moved then
		moved:Disconnect()
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	-- Streaming can add and remove it again before this deferred call runs.
	if not instance:IsDescendantOf(Workspace) or not CollectionService:HasTag(instance, TAG) then
		return
	end
	local model = instance
	local entry: Entry
	entry = {
		Model = model,
		Dirty = true,
		Hop = nil,
		NextHop = nil,
		HopSeen = nil,
		ShakeAt = nil,
		ShakeSeen = nil,
		Tilt = 0,
		Scale = nil,
		ScaleSeen = nil,
		Rest = nil,
		Written = nil,
		Land = false,
		Changed = model.AttributeChanged:Connect(function(name: string)
			if WATCHED[name] then
				if TIMES[name] then
					sample(model:GetAttribute(name))
				end
				entry.Dirty = true
				wake(entry)
			end
		end),
		Moved = nil,
	}
	tracked[model] = entry
	wake(entry) -- one that streamed in mid-hop carries on from where the server is
end

-- Nurses' sparkles: on or off for this client's reduced motion (see the header).
local sparkly: { [Instance]: RBXScriptConnection } = {}

local function applySparkles(model: Instance)
	local on = not Kit.reducedMotion()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Enabled ~= on then
			descendant.Enabled = on
		end
	end
end

local function watchSparkles(instance: Instance)
	if sparkly[instance] or not instance:IsA("Model") or instance:GetAttribute("NurseId") == nil then
		return
	end
	sparkly[instance] = instance.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = not Kit.reducedMotion()
		end
	end)
	applySparkles(instance)
end

local function unwatchSparkles(instance: Instance)
	local watcher = sparkly[instance]
	if watcher then
		watcher:Disconnect()
		sparkly[instance] = nil
	end
end

local function applyAllSparkles()
	for model in sparkly do
		applySparkles(model)
	end
end

function CreatureMotion.init(_ctx: Types.Ctx)
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
		task.defer(track, instance) -- streaming can hand over the Model a moment before its parts
		task.defer(watchSparkles, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		untrack(instance)
		unwatchSparkles(instance)
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		track(instance)
		watchSparkles(instance)
	end
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("ReduceEffects"):Connect(applyAllSparkles)
	end
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(applyAllSparkles)
	end)
end

return CreatureMotion
