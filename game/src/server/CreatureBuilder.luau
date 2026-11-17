--!strict
-- Builds a patient creature (build plan Task 1, §B1 kit overrides). Server only; Patients is the caller.
--   CreatureBuilder.build(patientId, variant?): Model
--     An original placeholder made from the patient's `Look` (Data/Patients, or Data/Regulars for a regular,
--     who uses their own id). BLOCKY (memory-20261117-004; look build plan §D T9): every part is a block. A chunky
--     body block and a head block (a Box is one slice of toast), feet, little block arms, the species' own ears
--     (rounded stacks, flops, cat peaks, bunny ears or tufts: never plain squares), a top, an extra (wings, a tail,
--     flippers, a spout) and its own Bits (a bell, glasses, a cherry...), so every species keeps its own silhouette.
--     A flat block face: big dark eyes with two white glints and a coloured strip, blush, a nose and a pixel mouth.
--     Studs only on the big top: one thin plate (`StudTop`) cut to whole studs at this creature's size and studded
--     through World/Studs; every other part is SmoothPlastic, so no 1-stud block shows cut-off studs. Colours are
--     the Look's brought down to world values (Pure.world: mid value, no pastel, no lerp toward white). Under 40
--     parts, so with the client's ailment props (Feel/CreatureActing) a creature stays under 45.
--     ServerStorage.Creatures.<PatientId> (a Model, or one MeshPart) replaces the placeholder look; its pivot's
--     LookVector must be the creature's face.
--     Size (Logic/CreatureSize): the species' Look.Scale x Config.CreatureSize x a per-patient wobble (±8%).
--     Night patients glow in a rich version of their body colour (a shadow-free PointLight, a Neon glow pad under
--     their feet and Neon on their tips; no Highlight). Sparkly gets rainbow bits and rainbow glitter; Frosty an icy
--     cyan tint and frost sparkles. Tagged CreatureBuilder.MOTION_TAG, so every client draws its hops
--     (Feel/CreatureMotion).
--   CreatureBuilder.badge(model): Badge?             the ailment badge (IconGui) and speech bubble (BubbleGui)
--   CreatureBuilder.setRing(badge, fraction, colour) the badge's ring: 0..1, filling clockwise from 12 o'clock
--   CreatureBuilder.setMood(model, mood)             "Sick" (a half-lid, a little o, worried brows) | "Happy" |
--                                                    "Sad" | "Sleep" (eyes closed, a sleepy smile)
--   CreatureBuilder.setEffect(model, name, on)       FX children: "Heal", "HealLight" (and the variant ones)
--   CreatureBuilder.effectAt(position, kind)         a one-off burst that outlives the creature:
--                                                    "Cure" | "Puff" (sad) | "Pop" (leaving)
--   CreatureBuilder.Pure                             the blocky layout in numbers (tests/BlockyCreatures.spec)
--
--   Depth update (build plan §B8; Foundation added these, T7 owns the file and keeps both signatures):
--   CreatureBuilder.buildLook(look, name?): Model    a plain creature from any Look (Data/Nurses uses the same
--                                                    recipe), built exactly like a patient (the blocky body, Root, Core
--                                                    on Root.PoseJoint, limb Motor6Ds, sockets; sized by Look.Scale
--                                                    x Config.CreatureSize, no wobble) with IconAnchor and a happy
--                                                    face, but no badge, no effects and no tags. NurseBuilder starts
--                                                    from it.
--   CreatureBuilder.rigKit(model): Model             the same Root, Core and PoseJoint (and guessed sockets) for a
--                                                    kit Model (NurseBuilder's ServerStorage.Nurses), so a nurse from
--                                                    the brother's kit follows the same rig conventions.
--   CreatureBuilder.setRecipe(badge, items, done)    show a patient's recipe on its badge (items = ItemIds in recipe
--                                                    order, done = booleans). One item: the Need chip, as before
--                                                    (hidden once given). Two or three: a row of item chips along
--                                                    the badge's bottom edge, the next one to give a little bigger,
--                                                    each given one dimmed with a ✅. Nothing left: no chips.
--
--   Progression v2 (build plan §B4/§C T7; OWNER: T7):
--   CreatureBuilder.setDept(badge, deptId?)          the department chip on the badge's left (Data/Departments
--                                                    icon: 🛏️ Wards, 🛁 Hydro), so a kid can pick the floor at
--                                                    triage; nil or "" hides it
--   CreatureBuilder.setUrgent(badge, urgent?)        "AE": a 🚑 chip (top left) and an orange rim round the badge;
--                                                    "VIP": a 🚁 chip and a cyan rim; nil or "": neither. Kid-safe:
--                                                    a friendly chip, nothing gory
--   build(patientId, "Golden")                       the 🌟 Golden variant (R3+): a gold sheen on the body, a gold
--                                                    sparkle emitter "Golden" under Root.FX (setEffect turns it on
--                                                    and off) and the 🌟 sticker. No extra parts
--
--   Creature motion (build plan §B4, the depth update's perf pass): the server never moves a creature every frame.
--   For each animation it sets attributes once, and every client draws the in-between (Feel/CreatureMotion). These
--   helpers only set attributes: they never yield and never move anything. The caller waits and then writes the end
--   pose once itself (Root.CFrame = to; Model:ScaleTo(to)), so late joiners and server checks see the right place.
--   CreatureBuilder.MOTION_TAG                       "CreatureMotion": build() tags patients; tag plot nurses too
--   CreatureBuilder.hop(model, from, to, seconds, height, spin?, lean?)   HopFrom/HopTo/HopSeconds/HopHeight/
--                                                    HopSpin/HopLean, then HopAt (server time) last
--   CreatureBuilder.shake(model)                     ShakeAt: a 0.55 s "no, not that" head-shake
--   CreatureBuilder.tilt(model, radians)             Tilt: a droop over everything else (0 = upright)
--   CreatureBuilder.scale(model, from, to, seconds, style, direction)   ScaleFrom/ScaleTo/ScaleSeconds/ScaleStyle
--                                                    ("Back"|"Sine"|"Quad")/ScaleDir ("In"|"Out"), then ScaleAt
--
-- Performance rules every creature keeps (build plan Review focus 4; docs/plan/2026-11-16-perf-budget.md): no
-- Highlight (the world keeps at most one, and creatures never use it), no light casts shadows, and only parts at
-- least SHADOW_STUDS across cast a shadow (the body's shadow covers the eyes, cheeks, feet and ears). A kit model
-- from ServerStorage.Creatures is held to the same rules: its Highlights are removed (with a warning) and its
-- lights' Shadows turned off.
--
-- Model layout (Patients, NurseBuilder and Feel/CreatureActing rely on it; the blocky rebuild keeps it exactly):
--   PrimaryPart `Root`: an invisible anchored part at the bottom centre of the body. The pivot IS Root.CFrame, and
--   its LookVector is where the face looks. Moving Root moves the whole creature with one replicated CFrame.
--   `Core`: an invisible part on Root, joined by the Motor6D Root.PoseJoint (C0 = C1 = identity). Every visible part
--   is welded to Core (unanchored, massless, no collision, no queries, CollisionGroup "Patients"), so each client can
--   lean, bob and shake the body by setting PoseJoint.Transform locally (never replicated) while the server moves
--   Root. The arms (or wings or flippers) hang on Motor6Ds Core.ArmRJoint / Core.ArmLJoint at the shoulder, and a
--   tail on Core.TailJoint, so a client can wave and wag them the same way. R is the creature's own right (+X; on
--   your left as it faces you). Each arm part has a HandSocket Attachment at its paw (a paw that holds props is a
--   part named "Arm").
--   Sockets: Attachments on Core where the client's props go (in studs, scaled with the creature): FaceSocket (the
--   mouth), NoseSocket, EyeRSocket/EyeLSocket, CheekRSocket/CheekLSocket, BrowSocket (the forehead), HeadSocket (top
--   of the head), EarRSocket/EarLSocket (the head's sides), NeckSocket (where head meets body), BellySocket,
--   BackSocket and, on a teapot, SpoutSocket. Each one's front (-Z) faces out of the surface; HeadSocket, NeckSocket
--   and SpoutSocket keep the model's own orientation.
--   Model attributes: PatientId, BuildScale (studs per unit at full size; Scale 1 is about 3 units tall), HeadRadius
--   (half the head's width) and NeckSize (studs: Vector3 width, 0, depth for a scarf round the neck), Brows
--   ("Grumpy" for a grumpy species).
--   Tags (CollectionService): "ClinicCreature" (Feel/CreatureActing acts its ailment) and MOTION_TAG
--   "CreatureMotion" (Feel/CreatureMotion draws its hops), so clients find every patient as it streams in.
--   CreatureMotion moves Root (its local CFrame) and the model's scale; CreatureActing only sets the Motor6Ds'
--   Transform under it, so the two never fight.
--   Root.IconAnchor (Attachment above the head) holds the BillboardGuis IconGui and BubbleGui. The badge is
--   chunky and outlined like the top games' billboards: a dark rim, the patience ring, the station's candy ring
--   and a white disc with the ailment, plus corner chips (what it needs, Today's Visitor ⭐, the variant).
--   Both are sized in studs, so they shrink with distance like real objects, but never grow past their size at
--   NEAR_STUDS (BillboardGui.DistanceLowerLimit): standing right next to a patient, its badge stays a small part
--   of the screen (first-session declutter, docs/plan/2026-11-16-first-session-design.md §A2).
--   Root.FX (Attachment at the body's middle) holds the lights and particle emitters.
--   Model:GetScale() is the creature's own size (BuildScale); Patients scales relative to it.
--   Face parts (setMood and Feel/CreatureProps rely on the names): Eye, EyeShine, EyeTint, EyeLid (the sick
--   half-lid), Lid (a see-through plate: LidGui draws the closed eyes; the client draws its squint on it), Brow
--   (BrowGui: Worried | Grumpy | Happy | Sad), Mouth (MouthGui: Sick | Happy | Sad | Smile) and Cheek. Only the
--   eyes' lids are named "Lid" (a teapot's top is "PotLid").
-- Rated Minimal: chunky, friendly blocks. Nothing sharp, scary or gross. Original (red line 2): our own recipes,
-- no other game's pets, and never a cross.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local CreatureSize = require(Shared.Logic.CreatureSize)
local Departments = require(Shared.Data.Departments)
local Items = require(Shared.Data.Items)
local Palette = require(Shared.Palette)
local PatientsData = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Stations = require(Shared.Data.Stations)
local Variants = require(Shared.Data.Variants)
local Studs = require(script.Parent.World.Studs)

local Candy = Palette.Candy

local CreatureBuilder = {}

export type Badge = {
	Gui: BillboardGui,
	Icon: TextLabel, -- the big emoji: the ailment, then 💗 / 💤 / 🥰 / 😔
	Need: Frame, -- the little chip with the item it needs
	Star: Frame, -- Today's Visitor ⭐
	Sticker: Frame, -- the variant sticker (✨ / 🧊 / 🌟)
	Dept: Frame, -- Progression v2: the department chip (setDept)
	Urgent: Frame, -- Progression v2: the 🚑 / 🚁 chip (setUrgent)
	Rim: Frame, -- the badge's outer rim (setUrgent colours it)
	FillLeft: Frame,
	FillRight: Frame,
	GradLeft: UIGradient,
	GradRight: UIGradient,
	Bubble: BillboardGui, -- a regular's speech bubble (disabled until shown)
	BubbleEmote: TextLabel,
	BubbleText: TextLabel,
}

type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
	Bits: { string }?,
}

type Build = {
	Model: Model,
	Tint: { BasePart }, -- coloured parts that Frosty, Sparkly and Golden tint (eyes, cheeks and face guis stay)
	Big: { [BasePart]: boolean }, -- the big parts: Sparkly brightens them instead of a rainbow
	Anchor: BasePart?, -- the Body part: the sockets ride on it until Core exists
	Rides: { [BasePart]: string }, -- a part that moves with an arm or the tail: that joint's key
	Joints: { [string]: BasePart }, -- "ArmR" | "ArmL" | "Tail": the part its Motor6D drives
}

type Rig = { Rides: { [BasePart]: string }, Joints: { [string]: BasePart } }

local COLLISION_GROUP = "Patients"
local CREATURE_TAG = "ClinicCreature" -- Feel/CreatureActing finds creatures by it
local ROOT_SIZE = 0.2 -- Root and Core (Feel/CreatureActing reads Root.Size / ROOT_SIZE as the pop-in scale)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WHITE = Palette.White
local EYE = Palette.Outline -- deep plum-navy, never pure black
local MOUTH = Palette.Ink
local LENS = Palette.Accent.Cyan
local GLASS_RIM = Color3.fromRGB(90, 58, 158)
local ICE = Color3.fromRGB(100, 206, 235) -- Frosty: icy cyan (a world value: no channel above 245)
local HEAL = Candy.Pink
local HEAL_LIGHT = Color3.fromRGB(255, 200, 236)
local SAD_PUFF = Color3.fromRGB(140, 132, 255) -- a soft periwinkle puff: sad, never scary
local RING_START = Candy.Lime -- the patience ring starts full and green
local TRACK = Color3.fromRGB(236, 232, 250) -- the empty part of the patience ring
local DEFAULT_STATION = Candy.Pink
local BUBBLE = Candy.Purple -- a regular's speech bubble (white outlined text reads best on it)
local STICKER_RING: { [string]: Color3 } = { Sparkly = Candy.Pink, Frosty = Candy.Cyan, Golden = Candy.Yellow }
local GOLD = Color3.fromRGB(240, 194, 62) -- Golden: a warm gold sheen (a world value)
local GOLD_LIGHT = Color3.fromRGB(255, 244, 190) -- its sparkles
local SPARKLY_VALUE = 0.94 -- Sparkly's brightest: a holo sticker, never bleached to white
-- An urgent patient's badge: its chip's ring and the badge's rim (never red: the patience ring's "hurry" colour).
local URGENT_RING: { [string]: Color3 } = { AE = Candy.Orange, VIP = Candy.Cyan }
local DEPT_RING = Candy.Mint
-- Each department chip's ring, the same colours as UI/MiniGames' triage floor buttons (its DEPT_KINDS: Theme.Colors
-- Primary / Danger / Pink / Cyan / Good / Purple), so a kid matches the badge to the button.
local DEPT_RINGS: { [string]: Color3 } = {
	Reception = Candy.Orange,
	AE = Candy.Red,
	Wards = Candy.Pink,
	Hydro = Candy.Cyan,
	Pharmacy = Candy.Lime,
	Roof = Candy.Purple,
}

-- Rainbow glitter for Sparkly, and the colours a cure bursts into.
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Candy.Pink),
	ColorSequenceKeypoint.new(0.2, Candy.Orange),
	ColorSequenceKeypoint.new(0.4, Candy.Yellow),
	ColorSequenceKeypoint.new(0.6, Candy.Lime),
	ColorSequenceKeypoint.new(0.8, Candy.Cyan),
	ColorSequenceKeypoint.new(1, Candy.Purple),
})
local CONFETTI = { Candy.Pink, Candy.Yellow, Candy.Cyan, Candy.Lime, Candy.Purple }

-- The badge: the IconGui is BADGE_STUDS square, and the round badge fills BADGE_FACE of it, so the corner chips and
-- the outlines stay inside the gui.
local BADGE_STUDS = 3.8
local BADGE_FACE = 0.8
-- Closer than this, the badge and the speech bubble stop growing on screen (about a fifth of its height at most).
local NEAR_STUDS = 16

-- Performance: only parts at least this many studs across (after scaling) cast a shadow.
local SHADOW_STUDS = 1.5
-- A night creature's glow pad under its feet (Neon, no Highlight): this much wider than the body, this see-through.
local GLOW_RING_WIDTH = 1.15
local GLOW_RING_TRANSPARENCY = 0.35

-- The face drawings (SurfaceGuis on see-through plates): sized in studs, hidden far away, lit a little.
local FACE_PIXELS = 100
local FACE_NEAR = 70

-- The recipe row on the badge (setRecipe): chip centres along the face's bottom edge, in face-relative scale.
local RECIPE_MAX = 3
local RECIPE_Y = 0.92
local TICK = "✅"
-- Each item's chip ring is the colour of the station that makes it.
local ITEM_RING: { [string]: Color3 } = {}
for _, itemId in Items.Order do
	local station = Stations[Items[itemId].Station]
	ITEM_RING[itemId] = if station then station.Color else DEFAULT_STATION
end

-- BEGIN PURE: no services; a scratch Lune harness loads this block on its own.
-- Where each of a recipe's chips sits along the bottom of the badge face (X centre, face-relative) and how big
-- (Size, face-relative), in recipe order. The first item still missing (`nextIndex`) is drawn a little bigger.
-- Fewer than 2 items: none (one item uses the Need chip).
local function recipeLayout(count: number, nextIndex: number?): { { X: number, Size: number } }
	local spots: { { X: number, Size: number } } = {}
	local xs = if count == 2 then { 0.3, 0.7 } elseif count >= 3 then { 0.14, 0.5, 0.86 } else {}
	for index, x in xs do
		table.insert(spots, { X = x, Size = if index == nextIndex then 0.42 else 0.34 })
	end
	return spots
end

-- Progression v2: an urgent patient's chip icon ("AE" 🚑, "VIP" 🚁), or nil for everyone else.
local function urgentIcon(urgent: any): string?
	if urgent == "AE" then
		return "🚑"
	elseif urgent == "VIP" then
		return "🚁"
	end
	return nil
end
-- END PURE

-- PURE-BEGIN
-- The blocky creature in numbers (memory-20261117-004; look build plan §D T9). No Roblox types in here:
-- tests/BlockyCreatures.spec loads this block on its own and checks what ships. Sizes and places are { X, Y, Z }
-- tables in units (Scale 1 is about 3 units tall; y = 0 is the ground under the creature; the face looks at -Z and
-- +X is the creature's own right, on your left), colours are "#RRGGBB" strings, and every part is a block.
--   Pure.layout(look, opts?): Layout   every part, socket and number of one creature. opts.Night: its tips glow;
--                                      opts.Scale: studs per unit (the stud plate is cut to whole studs at it)
--     Layout = { Parts, Sockets, Top, HeadHalf, Neck, Brows, Shape }
--     a part = { Name, Size, Pos, Rot? (radians: CFrame.Angles(X, Y, Z) about its centre), Color, Tint (variants
--       tint it), Big? (Sparkly brightens it instead of a rainbow), Studs? (the stud plate), Clear? (Transparency),
--       Shadow? (false: casts none), Neon? (Neon on a night creature), Gui? ("Lid" | "Brow" | "Mouth" | "Glasses"),
--       Side?, Gap? / Bar? / LensW? / LensH? (where a drawing's pieces sit on its plate), Ink? (a drawing's colour),
--       Joint? ("ArmR" | "ArmL" | "Tail") with Pivot (the shoulder or the tail's root), Ride? (moves with that
--       joint), Hand? / HandTilt? (a HandSocket at that point of the part) }
--     a socket = { Name, Pos, Normal? } (no Normal: the model's own orientation)
--   Pure.world(hex, role): string      a Look colour brought down to world values ("Body" | "Accent"): its hue
--                                      kept, saturation at least S_FLOOR, value at most the cap (V_CAP; yellows up
--                                      to V_CAP_YELLOW), so never a pastel and never a channel above 245. A white
--                                      accent becomes the warm white. Never a lerp toward white
--   Pure.mid(hex): string              only the value capped (the nurse cap keeps its rarity's hue; grey stays grey)
--   Pure.tone(hex, dv) · Pure.darken(hex, amount) · Pure.hsv(hex) · Pure.cap(hue)
--   Pure.studs(units, scale): number   the widest whole number of studs that fits in `units` at `scale`, in units
--   Pure.MOUTH · Pure.CLOSED_EYE        the pixel drawings: { col, row, width?, height? } cells on a Cols x Rows grid
--   Pure.BROWS · Pure.BROW_ORDER        each mood's brows: height on the plate and the right brow's turn in degrees
--   Pure.KNOWN_BITS                     every Look.Bits name the layout draws
local Pure = {}

Pure.MAX_PARTS = 40 -- every creature stays UNDER this, Root, Core and a night glow pad included
Pure.RIG_PARTS = 2 -- Root and Core: the layout doesn't list them
Pure.PLATE = 0.1 -- the stud plate's thickness (units)

type V3 = { X: number, Y: number, Z: number }

local function v(x: number, y: number, z: number): V3
	return { X = x, Y = y, Z = z }
end

local FRONT = v(0, 0, -1)
local BACK = v(0, 0, 1)

-- Fixed colours, at world values (art-direction §4.1): no pure white and no channel above 245 on a creature.
local INK_EYE = "#1B1238" -- Palette.Outline: deep plum-navy, never black
local GLINT = "#F5F3EE"
local CHEEK = "#E0679C"
local CREAM = "#EDE7DA" -- the warm white: wool, ruffs, petals, dots, a white accent
local LEAF = "#6ACC39" -- Palette.Accent.Lime
local STEM = "#2E9E3E"
local NOSE_DARK = "#52342C" -- a pup's nose: warm cocoa, not black
local NOSE_PINK = "#E0709A"
local PAW_PINK = "#E58AA8"
local BEAK = "#EB842A" -- Palette.Accent.Orange
local GOLDEN = "#F5C731" -- Palette.Accent.Yellow: a bell, a star, a flower's middle
local CHERRY = "#D63C4B" -- Palette.Accent.Red (a prop: never a cross)
local BUTTER = "#F0D27A"
local SYRUP = "#DB3D7D"
local SYRUP_BLUE = "#29BCCC"
local FALLBACK_BODY = "#D6459A"
Pure.WARM_WHITE = CREAM
Pure.EYE = INK_EYE

local V_CAP, V_CAP_YELLOW, V_FLOOR = 0.86, 0.94, 0.3
local S_FLOOR: { [string]: number } = { Body = 0.42, Accent = 0.35 }
local WHITE_S = 0.15 -- an accent this pale (and light) is a white: it becomes the warm white
Pure.V_CAP, Pure.V_CAP_YELLOW, Pure.V_FLOOR, Pure.S_FLOOR = V_CAP, V_CAP_YELLOW, V_FLOOR, S_FLOOR

local function rgb(hex: any): { number }?
	if type(hex) ~= "string" then
		return nil
	end
	local r, g, b = string.match(hex, "^#?(%x%x)(%x%x)(%x%x)$")
	if not (r and g and b) then
		return nil
	end
	return {
		(tonumber(r, 16) :: number) / 255,
		(tonumber(g, 16) :: number) / 255,
		(tonumber(b, 16) :: number) / 255,
	}
end

local function toHex(r: number, g: number, b: number): string
	local function byte(c: number): number
		return math.clamp(math.floor(c * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", byte(r), byte(g), byte(b))
end

-- Hue (0..1), saturation and value of an { r, g, b } colour.
local function toHsv(c: { number }): (number, number, number)
	local r, g, b = c[1], c[2], c[3]
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local delta = high - low
	local h = 0
	if delta > 1e-9 then
		if high == r then
			h = ((g - b) / delta) % 6
		elseif high == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	return h, if high > 1e-9 then delta / high else 0, high
end

local function fromHsv(h: number, s: number, value: number): string
	local sector = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = value * (1 - s), value * (1 - f * s), value * (1 - (1 - f) * s)
	if sector == 0 then
		return toHex(value, t, p)
	elseif sector == 1 then
		return toHex(q, value, p)
	elseif sector == 2 then
		return toHex(p, value, t)
	elseif sector == 3 then
		return toHex(p, q, value)
	elseif sector == 4 then
		return toHex(t, p, value)
	end
	return toHex(value, p, q)
end

-- The value a world colour may reach at hue h (0..1): yellows and golds sit a little higher, like Palette's Yellow.
function Pure.cap(h: number): number
	local near = math.max(0, 1 - math.abs(h * 360 - 52) / 30)
	return V_CAP + (V_CAP_YELLOW - V_CAP) * near
end

function Pure.hsv(hex: any): (number, number, number)
	local c = rgb(hex)
	if not c then
		return 0, 0, 0
	end
	return toHsv(c)
end

function Pure.world(hex: any, role: string): string
	local c = rgb(hex)
	if not c then
		return if role == "Accent" then CREAM else FALLBACK_BODY
	end
	local h, s, value = toHsv(c)
	if role == "Accent" and s < WHITE_S and value > 0.7 then
		return CREAM
	end
	if s >= 0.06 then -- a true grey keeps its greyness
		s = math.max(s, S_FLOOR[role] or S_FLOOR.Body)
	end
	return fromHsv(h, s, math.clamp(value, V_FLOOR, Pure.cap(h)))
end

function Pure.mid(hex: any): string
	local c = rgb(hex)
	if not c then
		return FALLBACK_BODY
	end
	local h, s, value = toHsv(c)
	return fromHsv(h, s, math.min(value, Pure.cap(h)))
end

-- Lighter or darker by `dv` in value, never past the world cap: a lighter tone without a lerp toward white.
function Pure.tone(hex: any, dv: number): string
	local c = rgb(hex)
	if not c then
		return FALLBACK_BODY
	end
	local h, s, value = toHsv(c)
	return fromHsv(h, s, math.clamp(value + dv, V_FLOOR, Pure.cap(h)))
end

-- A darker shade (toward black, never toward white).
function Pure.darken(hex: any, amount: number): string
	local c = rgb(hex) or { 0.5, 0.5, 0.5 }
	local k = 1 - math.clamp(amount, 0, 1)
	return toHex(c[1] * k, c[2] * k, c[3] * k)
end

local function mix(a: string, b: string, t: number): string
	local ca, cb = rgb(a) or { 0, 0, 0 }, rgb(b) or { 0, 0, 0 }
	return toHex(ca[1] + (cb[1] - ca[1]) * t, ca[2] + (cb[2] - ca[2]) * t, ca[3] + (cb[3] - ca[3]) * t)
end

-- The stud plate's width: whole studs at this creature's size, so no stud is cut at an edge (World/Studs' rule).
function Pure.studs(units: number, scale: number): number
	local s = if scale > 0 then scale else 1
	local n = math.floor(units * s + 1e-6)
	if n < 1 then
		return units
	end
	return n / s
end

-- (x, y) turned by `a` radians about Z, as CFrame.Angles(0, 0, a) turns it (+X toward +Y).
local function turn(x: number, y: number, a: number): (number, number)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

-- The pixel mouth (MouthGui): one drawing per mood on a 9 x 5 grid.
Pure.MOUTH = {
	Cols = 9,
	Rows = 5,
	Sick = { { 4, 1.5, 1, 2 } }, -- a little "o" (CreatureProps' extra mouths cover it whole)
	Happy = { { 1, 1.5 }, { 4, 1.5 }, { 7, 1.5 }, { 2, 2.5, 2, 1 }, { 5, 2.5, 2, 1 } }, -- a wide "w"
	Sad = { { 3, 1.5, 3, 1 }, { 2, 2.5 }, { 6, 2.5 } }, -- a little frown
	Smile = { { 2, 1.5 }, { 6, 1.5 }, { 3, 2.5, 3, 1 } }, -- a closed, sleepy smile
}
Pure.MOUTH_ORDER = { "Sick", "Happy", "Sad", "Smile" }
-- Closed, contented eyes (LidGui, setMood "Sleep"): a little cup on a 5 x 5 grid.
Pure.CLOSED_EYE = { Cols = 5, Rows = 5, Cells = { { 0, 2 }, { 4, 2 }, { 1, 3, 3, 1 } } }
-- The brows (BrowGui): height on the plate (0 top .. 1 bottom) and the creature's right brow's turn in degrees,
-- clockwise as you look at it (the left brow turns the other way). Flat blocks, no rounding.
Pure.BROWS = {
	Worried = { Y = 0.55, Turn = -14 }, -- inner ends up
	Grumpy = { Y = 0.62, Turn = 20 }, -- inner ends down
	Sad = { Y = 0.62, Turn = -26 },
	Happy = { Y = 0.32, Turn = 0 }, -- raised
}
Pure.BROW_ORDER = { "Worried", "Grumpy", "Sad", "Happy" }

Pure.KNOWN_BITS = {
	Toes = true,
	Spots = true,
	Bell = true,
	Nose = true,
	PinkNose = true,
	Butter = true,
	Cherry = true,
	CottonTail = true,
	Whiskers = true,
	Puddle = true,
	Glasses = true,
	PinkPaws = true,
	Beak = true,
	OrangeFeet = true,
	Syrup = true,
	EyeRings = true,
	Hem = true,
	MothWings = true,
	WingSpots = true,
	Fluff = true,
	Daisy = true,
	Blush = true,
	Dots = true,
	GrumpyBrows = true,
	Trail = true,
}

-- Each Shape's blocks (W, H, D in units), how high its body starts (Lift: its feet go under it), its feet, and where
-- the eyes sit on the face block (EyeX from the middle, EyeY above the face block's bottom; Eye = the face's scale).
local SHAPES: { [string]: any } = {
	-- A big head on a small body: the toy proportions.
	Ball = {
		Body = { 1.9, 1.0, 1.5 },
		Head = { 2.7, 1.65, 2.0 },
		Lift = 0.35,
		Foot = { 0.8, 0.4, 1.0 },
		FootX = 0.5,
		EyeX = 0.58,
		EyeY = 0.95,
		Eye = 1,
	},
	-- Taller and slimmer: a longer body under a narrower head.
	Bean = {
		Body = { 1.75, 1.4, 1.5 },
		Head = { 2.3, 1.5, 1.85 },
		Lift = 0.3,
		Foot = { 0.7, 0.35, 0.9 },
		FootX = 0.46,
		EyeX = 0.5,
		EyeY = 0.86,
		Eye = 0.92,
	},
	-- Wide and low.
	Blob = {
		Body = { 2.8, 0.75, 2.1 },
		Head = { 3.2, 1.3, 2.3 },
		Lift = 0.25,
		Foot = { 0.95, 0.3, 0.9 },
		FootX = 0.85,
		EyeX = 0.62,
		EyeY = 0.72,
		Eye = 0.95,
	},
	-- One tall slice (of toast): its face is on its front.
	Box = {
		Body = { 2.6, 2.3, 1.3 },
		Lift = 0.33,
		Foot = { 0.75, 0.38, 0.9 },
		FootX = 0.62,
		EyeX = 0.5,
		EyeY = 1.45,
		Eye = 0.95,
	},
	-- A stepped drop: a wide base and a narrower head on it, no feet (a jelly, a slime, a ghost).
	Drop = {
		Body = { 2.5, 1.1, 2.2 },
		Head = { 2.2, 1.55, 1.9 },
		Lift = 0,
		EyeX = 0.5,
		EyeY = 0.84,
		Eye = 0.92,
	},
}
Pure.SHAPES = SHAPES

function Pure.layout(look: any, opts: any?): any
	local o = if type(opts) == "table" then opts else {}
	local night = o.Night == true
	local scale = if type(o.Scale) == "number" and o.Scale > 0 then o.Scale else 1
	local recipe = if type(look) == "table" then look else {}
	local shapeName = if type(recipe.Shape) == "string" and SHAPES[recipe.Shape] then recipe.Shape else "Ball"
	local shape = SHAPES[shapeName]
	local box = shapeName == "Box"
	local function kind(value: any): string
		return if type(value) == "string" then value else "None"
	end
	local ears, top, extra = kind(recipe.Ears), kind(recipe.Top), kind(recipe.Extra)
	local bits: { [string]: boolean } = {}
	if type(recipe.Bits) == "table" then
		for _, name in recipe.Bits do
			if type(name) == "string" then
				bits[name] = true
			end
		end
	end
	local body = Pure.world(recipe.Body, "Body")
	local accent = Pure.world(recipe.Accent, "Accent")

	local parts = {}
	local sockets = {}
	local function add(name: string, size: V3, pos: V3, color: string, tint: boolean, more: { [string]: any }?): any
		local spec: { [string]: any } = { Name = name, Size = size, Pos = pos, Color = color, Tint = tint }
		if more then
			for key, value in more do
				spec[key] = value
			end
		end
		table.insert(parts, spec)
		return spec
	end
	local function socket(name: string, pos: V3, normal: V3?)
		table.insert(sockets, { Name = name, Pos = pos, Normal = normal })
	end
	local function tag(side: number): string
		return if side > 0 then "R" else "L"
	end

	-- The body, and the head on it. A Box is one slice: its face is on its bread front.
	local lift = if shapeName == "Drop" and bits.Hem then 0.3 else shape.Lift
	local bw, bh, bd = shape.Body[1], shape.Body[2], shape.Body[3]
	local bodyY, bodyTop = lift + bh / 2, lift + bh
	add("Body", v(bw, bh, bd), v(0, bodyY, 0), body, true, { Big = true })
	local face: { W: number, H: number, D: number, Bottom: number, Top: number, Y: number }
	if shape.Head then
		local hw, hh, hd = shape.Head[1], shape.Head[2], shape.Head[3]
		local bottom = bodyTop - 0.05
		add("Head", v(hw, hh, hd), v(0, bottom + hh / 2, 0), body, true, { Big = true })
		face = { W = hw, H = hh, D = hd, Bottom = bottom, Top = bottom + hh, Y = bottom + hh / 2 }
	else
		face = { W = bw, H = bh, D = bd, Bottom = lift, Top = bodyTop, Y = bodyY }
	end
	local skin = if box then accent else body -- the colour around the eyes

	-- The belly patch (a Box's whole bread front, which carries its face).
	local bellyPos: V3, bellyFront: number, faceZ: number
	if box then
		bellyPos = v(0, bodyY - 0.05, -bd / 2 - 0.05)
		add("Belly", v(bw - 0.4, bh - 0.4, 0.1), bellyPos, accent, true, { Big = true })
		bellyFront = -bd / 2 - 0.1
		faceZ = bellyFront
	else
		local w, h = bw * 0.58, bh * 0.66
		bellyPos = v(0, lift + bh * 0.1 + h / 2, -bd / 2 - 0.04)
		add("Belly", v(w, h, 0.08), bellyPos, accent, true, { Big = true })
		bellyFront = -bd / 2 - 0.08
		faceZ = -face.D / 2
	end

	-- The face: flat blocks on the face block's front (faceZ), stacked a few hundredths apart so nothing flickers.
	local es = shape.Eye
	local eyeX = shape.EyeX
	local eyeY = face.Bottom + shape.EyeY
	local bigNose = bits.Nose or bits.PinkNose or bits.Beak
	local noseY = eyeY - 0.32 * es
	local mouthY = eyeY - (if bigNose then 0.6 else 0.5) * es
	local lower = faceZ -- the front the nose and mouth sit on: the face, or a muzzle
	local muzzleW, muzzleY = 0.98 * es, eyeY - 0.45 * es
	if (bits.Nose or bits.PinkNose or bits.Whiskers) and not box then
		add("Muzzle", v(muzzleW, 0.52 * es, 0.12), v(0, muzzleY, faceZ - 0.06), accent, true, { Big = true })
		lower = faceZ - 0.12
	end

	local eyeFront = faceZ - 0.08
	local h = Pure.hsv(body)
	local strip = mix(INK_EYE, fromHsv(h, 0.6, 0.85), 0.45) -- a soft glow of colour at the bottom of each eye
	for _, side in { 1, -1 } do
		local x = side * eyeX
		add("Eye", v(0.44 * es, 0.56 * es, 0.08), v(x, eyeY, faceZ - 0.04), INK_EYE, false)
		add("EyeTint", v(0.3 * es, 0.1 * es, 0.03), v(x, eyeY - 0.2 * es, eyeFront - 0.015), strip, false)
		-- Two white glints in the same corner of both eyes: the "alive and friendly" look.
		local big, small = 0.16 * es, 0.08 * es
		add("EyeShine", v(big, big, 0.03), v(x + 0.07 * es, eyeY + 0.1 * es, eyeFront - 0.015), GLINT, false)
		add("EyeShine", v(small, small, 0.03), v(x - 0.08 * es, eyeY - 0.06 * es, eyeFront - 0.015), GLINT, false)
		-- The sick half-lid: the face's own colour over the top half of the eye (setMood "Sick" shows it).
		add("EyeLid", v(0.48 * es, 0.27 * es, 0.06), v(x, eyeY + 0.145 * es, eyeFront - 0.03), skin, true, {
			Big = true,
			Clear = 1,
			Shadow = false,
		})
		-- A see-through plate in front of it all: the closed eyes (setMood "Sleep") and the client's squint.
		add("Lid", v(0.5 * es, 0.62 * es, 0.02), v(x, eyeY, eyeFront - 0.08), GLINT, false, {
			Clear = 1,
			Gui = "Lid",
			Side = side,
		})
		socket("Eye" .. tag(side) .. "Socket", v(x, eyeY, eyeFront - 0.1), FRONT)

		local cx, cy = side * (eyeX + 0.4 * es), eyeY - 0.36 * es
		local cheek = if bits.Blush then v(0.5 * es, 0.24 * es, 0.06) else v(0.4 * es, 0.18 * es, 0.06)
		add("Cheek", cheek, v(cx, cy, faceZ - 0.03), CHEEK, false)
		socket("Cheek" .. tag(side) .. "Socket", v(cx, cy, faceZ - 0.06), FRONT)
	end

	-- One brow plate over both eyes (BrowGui draws both brows per mood).
	local browW = 2 * eyeX + 0.6 * es
	add("Brow", v(browW, 0.24 * es, 0.02), v(0, eyeY + 0.43 * es, faceZ - 0.012), GLINT, false, {
		Clear = 1,
		Gui = "Brow",
		Gap = eyeX / browW,
		Bar = 0.42 * es / browW,
		Ink = mix(Pure.darken(skin, 0.55), INK_EYE, 0.35),
	})

	-- The nose: the species' own (a cocoa pup nose, a big pink one, a beak), or a small one of its colour.
	local noseFront: number
	if bits.Beak then
		add("Beak", v(0.46 * es, 0.2 * es, 0.36 * es), v(0, noseY, lower - 0.18 * es), BEAK, true)
		add("BeakTip", v(0.3 * es, 0.12 * es, 0.22 * es), v(0, noseY - 0.15 * es, lower - 0.11 * es), BEAK, true)
		noseFront = lower - 0.36 * es
	elseif bits.Nose or bits.PinkNose then
		local pink = bits.PinkNose == true
		local size = if pink then v(0.42 * es, 0.3 * es, 0.24 * es) else v(0.3 * es, 0.2 * es, 0.16 * es)
		add("Nose", size, v(0, noseY, lower - size.Z / 2), if pink then NOSE_PINK else NOSE_DARK, false)
		local shine = v(size.X * 0.22, noseY + size.Y * 0.24, lower - size.Z - 0.01)
		add("NoseShine", v(0.08 * es, 0.05 * es, 0.02), shine, GLINT, false)
		noseFront = lower - size.Z
	else
		add("Nose", v(0.18 * es, 0.12 * es, 0.08), v(0, noseY, lower - 0.04), Pure.darken(skin, 0.45), false)
		noseFront = lower - 0.08
	end
	socket("NoseSocket", v(0, noseY, noseFront - 0.02), FRONT)

	-- The pixel mouth: a see-through plate (MouthGui draws each mood).
	add("Mouth", v(0.62 * es, 0.3 * es, 0.02), v(0, mouthY, lower - 0.012), GLINT, false, { Clear = 1, Gui = "Mouth" })
	socket("FaceSocket", v(0, mouthY, lower - 0.03), FRONT)
	socket("BrowSocket", v(0, math.min(eyeY + 0.92 * es, face.Top - 0.3), faceZ - 0.02), FRONT)

	-- Feet, a little ahead of the body.
	if shape.Foot then
		local fw, fh, fd = shape.Foot[1], shape.Foot[2], shape.Foot[3]
		local color = if bits.OrangeFeet then BEAK else Pure.darken(body, 0.14)
		local fz = -bd / 2 + fd / 2 - 0.15
		for _, side in { 1, -1 } do
			local fx = side * shape.FootX
			add("Foot", v(fw, fh, fd), v(fx, fh / 2, fz), color, true)
			if bits.Toes then
				add(
					"Toe",
					v(fw * 0.8, fh * 0.45, 0.14),
					v(fx, fh * 0.225, fz - fd / 2 - 0.06),
					Pure.tone(color, 0.12),
					true
				)
			end
		end
	end

	-- Little block arms, hanging from the shoulders (unless wings or flippers are its arms). Each one is a part named
	-- "Arm" on its own Motor6D, with a HandSocket at its paw.
	if extra ~= "Wings" and extra ~= "Flippers" then
		local color = if bits.PinkPaws then PAW_PINK else Pure.darken(body, 0.06)
		local sy = if box then bodyY - 0.1 else bodyTop - 0.12
		local sz = -bd * 0.18
		for _, side in { 1, -1 } do
			local tilt = side * 0.12
			local sx = side * (bw / 2 + 0.03)
			local ox, oy = turn(side * 0.12, -0.31, tilt) -- tucked against the body: the line is 7 studs apart
			add("Arm", v(0.38, 0.66, 0.4), v(sx + ox, sy + oy, sz), color, true, {
				Big = true,
				Rot = v(0, 0, tilt),
				Joint = if side > 0 then "ArmR" else "ArmL",
				Pivot = v(sx, sy, sz),
				Hand = v(0, -0.3, -0.06),
				HandTilt = tilt,
			})
		end
	end

	-- The top block (the head, a Box's slice, or a loaf of crust) and its stud plate.
	local cap = { W = face.W, D = face.D, Top = face.Top, Color = body }
	if top == "Crust" then
		local crust = Pure.darken(body, 0.15)
		if box then -- a loaf top: two stepped blocks of crust
			add("Crust", v(bw + 0.1, 0.34, bd + 0.1), v(0, bodyTop + 0.15, 0), crust, true, { Big = true })
			add("Crust", v(bw - 0.5, 0.26, bd), v(0, bodyTop + 0.43, 0), crust, true, { Big = true })
			cap = { W = bw - 0.5, D = bd, Top = bodyTop + 0.56, Color = crust }
		else
			add("Crust", v(face.W * 0.7, 0.36, face.D * 0.7), v(0, face.Top + 0.16, 0), crust, true, { Big = true })
			cap = { W = face.W * 0.7, D = face.D * 0.7, Top = face.Top + 0.34, Color = crust }
		end
	end
	local plated = top ~= "Pleat" and top ~= "Scoop" -- a wrapper or a scoop covers the whole top
	if plated then
		local size = v(Pure.studs(cap.W, scale), Pure.PLATE, Pure.studs(cap.D, scale))
		add("StudTop", size, v(0, cap.Top + Pure.PLATE / 2, 0), cap.Color, true, {
			Big = true,
			Studs = true,
			Shadow = false,
		})
	end
	local T = cap.Top + (if plated then Pure.PLATE else 0) -- the top of the head

	-- Ears: each kind its own shape (square ears read cat-like): a rounded stack, a flop, a peak, a long ear, tufts.
	for _, side in { 1, -1 } do
		if ears == "Round" then
			local x = side * (cap.W / 2 - 0.45)
			add("Ear", v(0.85, 0.4, 0.5), v(x, cap.Top + 0.18, 0.15), body, true)
			add("Ear", v(0.5, 0.22, 0.5), v(x, cap.Top + 0.47, 0.15), body, true)
		elseif ears == "Floppy" then
			local a = side * 0.15
			local ox, oy = turn(side * 0.14, -0.55, a)
			local px, py = side * (face.W / 2 + 0.05), face.Top - 0.1
			add(
				"Ear",
				v(0.3, 1.1, 0.8),
				v(px + ox, py + oy, 0.05),
				Pure.darken(accent, 0.06),
				true,
				{ Rot = v(0, 0, a) }
			)
		elseif ears == "Long" then
			local a = -side * 0.12
			local px, py = side * face.W * 0.2, cap.Top - 0.05
			local ox, oy = turn(0, 0.72, a)
			add("Ear", v(0.42, 1.44, 0.3), v(px + ox, py + oy, 0.1), body, true, { Rot = v(0, 0, a) })
			local ix, iy = turn(0, 0.76, a)
			add("EarInner", v(0.2, 1.0, 0.06), v(px + ix, py + iy, -0.08), accent, true, { Rot = v(0, 0, a) })
		elseif ears == "Pointy" then
			local x = side * (cap.W / 2 - 0.45)
			add("Ear", v(0.7, 0.36, 0.42), v(x, cap.Top + 0.16, 0.1), body, true)
			add("Ear", v(0.34, 0.34, 0.42), v(x + side * 0.13, cap.Top + 0.49, 0.1), body, true)
		elseif ears == "Tufts" then
			local color = Pure.darken(body, 0.12)
			local px, py = side * (cap.W / 2 - 0.3), cap.Top - 0.05
			local a, b = -side * 0.45, -side * 0.2
			local ox, oy = turn(0, 0.36, a)
			add("Ear", v(0.26, 0.76, 0.3), v(px + ox, py + oy, 0.05), color, true, { Rot = v(0, 0, a) })
			local qx, qy = turn(0, 0.25, b)
			add("Ear", v(0.2, 0.52, 0.26), v(px - side * 0.3 + qx, py + qy, 0.05), color, true, { Rot = v(0, 0, b) })
		end
	end

	-- The top.
	local scoop: { Y: number, Top: number, Front: number }? = nil
	if top == "Leaf" then
		add("Stem", v(0.14, 0.5, 0.14), v(0, T + 0.22, 0.05), STEM, false)
		add("Leaf", v(0.85, 0.12, 0.45), v(0.36, T + 0.5, 0.05), LEAF, false, { Rot = v(0, 0, 0.4) })
		add("Leaf", v(0.62, 0.1, 0.34), v(-0.27, T + 0.43, 0.05), LEAF, false, { Rot = v(0, 0, -0.45) })
	elseif top == "Bow" then
		for _, side in { 1, -1 } do
			add("Bow", v(0.62, 0.46, 0.26), v(side * 0.37, T + 0.24, 0), accent, true, { Rot = v(0, 0, side * 0.25) })
		end
		add("BowKnot", v(0.3, 0.3, 0.32), v(0, T + 0.24, -0.02), Pure.darken(accent, 0.08), true)
	elseif top == "Cloud" then -- a soft stack of wool
		add("Puff", v(1.3, 0.62, 1.25), v(0, T + 0.3, 0.05), CREAM, true)
		for _, side in { 1, -1 } do
			add("Puff", v(0.85, 0.46, 1.0), v(side * 0.8, T + 0.2, 0.1), CREAM, true)
		end
		add("Puff", v(0.7, 0.32, 0.7), v(0.12, T + 0.75, 0.1), CREAM, true)
	elseif top == "Antennae" then -- toward the front of the head, so they stand in front of any ears
		local az = -face.D / 2 + 0.45
		for _, side in { 1, -1 } do
			local a = -side * 0.35
			local bx, by = side * 0.3, T - 0.04
			local sx, sy = turn(0, 0.4, a)
			local stalk = Pure.darken(body, 0.2)
			add("Antenna", v(0.1, 0.8, 0.1), v(bx + sx, by + sy, az), stalk, true, { Rot = v(0, 0, a) })
			local tx, ty = turn(0, 0.86, a)
			add("AntennaTip", v(0.3, 0.3, 0.3), v(bx + tx, by + ty, az), accent, true, {
				Rot = v(0, 0, a),
				Neon = true,
			})
		end
	elseif top == "Pleat" then -- a dumpling wrapper, pinched at the top
		add("Wrap", v(face.W * 0.8, 0.3, face.D * 0.8), v(0, T + 0.13, 0.05), accent, true)
		for _, side in { 1, -1 } do
			local pleat = Pure.darken(accent, 0.07)
			add("Pleat", v(0.24, 0.42, face.D * 0.55), v(side * 0.34, T + 0.42, 0.05), pleat, true, {
				Rot = v(0, 0, -side * 0.35),
			})
		end
		add("Knot", v(0.48, 0.36, 0.48), v(0, T + 0.5, 0.05), accent, true)
	elseif top == "Scoop" then -- a snow cone's ice on a snowy rim
		add("Snow", v(face.W * 0.86, 0.22, face.D * 0.86), v(0, T + 0.09, 0.05), accent, true)
		local sw, sh, sd = face.W * 0.68, 0.95, face.D * 0.68
		local sy = T + 0.18 + sh / 2
		add("Scoop", v(sw, sh, sd), v(0, sy, 0.05), accent, true)
		scoop = { Y = sy, Top = sy + sh / 2, Front = 0.05 - sd / 2 }
	elseif top == "Star" then -- an eight-point star from two blocks (never a plus: a plus reads as a cross)
		local hs = Pure.hsv(body) * 360
		local color = if hs >= 38 and hs <= 70 then BEAK else GOLDEN
		-- The turned square sits a little in front, so the two never share a face (no flicker).
		local turned = { Rot = v(0, 0, math.pi / 4), Neon = true }
		add("Star", v(0.72, 0.72, 0.2), v(0, T + 0.5, 0.05), color, true, { Neon = true })
		add("StarRay", v(0.72, 0.72, 0.2), v(0, T + 0.5, 0.02), color, true, turned)
	elseif top == "Lid" then -- a teapot's lid and knob
		add("PotLid", v(face.W * 0.6, 0.22, face.D * 0.6), v(0, T + 0.1, 0.05), accent, true)
		add("Knob", v(0.4, 0.3, 0.4), v(0, T + 0.35, 0.05), accent, true)
	end
	if shapeName == "Drop" and ears == "None" and top == "None" and not bits.Cherry then
		add("Tip", v(0.42, 0.36, 0.42), v(0, T + 0.16, 0.08), body, true, { Neon = true }) -- a little curl on top
	end

	-- The extra: wings, flippers, a tail or a spout. Wings and flippers are its arms (they flap and wave).
	if extra == "Wings" and bits.MothWings then -- big wings spread up and out behind it
		local color = Pure.tone(body, 0.1)
		local sz = math.max(bd, face.D) / 2 + 0.08
		for _, side in { 1, -1 } do
			local a = side * 0.5
			local sx, sy = side * bw * 0.25, bodyTop - 0.15
			local ox, oy = turn(side * 0.78, 0.1, a)
			add("Wing", v(1.5, 1.15, 0.12), v(sx + ox, sy + oy, sz), color, true, {
				Rot = v(0, 0, a),
				Joint = if side > 0 then "ArmR" else "ArmL",
				Pivot = v(sx, sy, sz),
				Hand = v(side * 0.7, 0, 0),
				HandTilt = a,
			})
			if bits.WingSpots then
				local px, py = turn(side * 0.98, 0.15, a)
				add("WingSpot", v(0.55, 0.42, 0.06), v(sx + px, sy + py, sz + 0.09), accent, true, {
					Rot = v(0, 0, a),
					Ride = if side > 0 then "ArmR" else "ArmL",
				})
			end
		end
	elseif extra == "Wings" then -- folded wings at the sides: short and thick, so they never read as legs
		local sy = bodyTop - 0.1
		local length = math.min(0.85, sy - 0.25)
		for _, side in { 1, -1 } do
			local tilt = side * 0.14
			local sx, sz = side * (bw / 2 + 0.02), 0.15
			local ox, oy = turn(side * 0.15, -length / 2, tilt)
			add("Wing", v(0.34, length, 0.95), v(sx + ox, sy + oy, sz), accent, true, {
				Rot = v(0, 0, tilt),
				Joint = if side > 0 then "ArmR" else "ArmL",
				Pivot = v(sx, sy, sz),
				Hand = v(0, -length / 2, -0.1),
				HandTilt = tilt,
			})
			if bits.WingSpots then
				local px, py = turn(side * 0.2, -length / 2 - 0.05, tilt)
				add("WingSpot", v(0.06, 0.45, 0.45), v(sx + px, sy + py, sz), Pure.darken(accent, 0.1), true, {
					Rot = v(0, 0, tilt),
					Ride = if side > 0 then "ArmR" else "ArmL",
				})
			end
		end
	elseif extra == "Flippers" then
		local color = Pure.darken(body, 0.15)
		for _, side in { 1, -1 } do
			local tilt = side * 0.42
			local sx, sy = side * (bw / 2 - 0.02), bodyY + 0.15
			local ox, oy = turn(side * 0.1, -0.48, tilt)
			add("Flipper", v(0.26, 1.0, 0.6), v(sx + ox, sy + oy, 0), color, true, {
				Rot = v(0, 0, tilt),
				Joint = if side > 0 then "ArmR" else "ArmL",
				Pivot = v(sx, sy, 0),
				Hand = v(0, -0.48, -0.05),
				HandTilt = tilt,
			})
		end
	elseif extra == "Tail" then
		local back = bd / 2
		if bits.Trail then -- a comet's trail: blocks streaming back and up, fading as they go (glowing at night)
			local sizes = { 0.8, 0.64, 0.5, 0.36 }
			for i, d in sizes do
				local more: { [string]: any } = { Clear = (i - 1) * 0.1, Neon = i >= 3 }
				if i == 1 then
					more.Joint, more.Pivot = "Tail", v(0, lift + 0.8, back - 0.1)
				else
					more.Ride = "Tail"
				end
				local at = v(0, lift + 0.75 + i * 0.24, back - 0.1 + i * 0.42)
				add(if i == #sizes then "TailTip" else "Tail", v(d, d, d), at, accent, true, more)
			end
		else -- a little stepped tail, up and back
			add("Tail", v(0.5, 0.5, 0.5), v(0, lift + 0.4, back + 0.2), body, true, {
				Joint = "Tail",
				Pivot = v(0, lift + 0.4, back - 0.05),
			})
			add("Tail", v(0.42, 0.42, 0.42), v(0, lift + 0.74, back + 0.5), body, true, { Ride = "Tail" })
			add("TailTip", v(0.36, 0.36, 0.36), v(0, lift + 1.04, back + 0.66), accent, true, {
				Ride = "Tail",
				Neon = true,
			})
		end
	elseif extra == "Spout" then -- a teapot: a spout on its right, a handle on its left (the head is the pot)
		local pot = Pure.darken(body, 0.05)
		local a = 0.7
		local rx, ry = face.W / 2 + 0.05, face.Y - 0.2
		local cx, cy = turn(0.42, 0, a)
		add("Spout", v(0.84, 0.36, 0.36), v(rx + cx, ry + cy, 0), pot, true, { Rot = v(0, 0, a) })
		local tx, ty = turn(0.94, 0, a)
		add("SpoutTip", v(0.42, 0.42, 0.42), v(rx + tx, ry + ty, 0), pot, true, { Rot = v(0, 0, a) })
		add("Handle", v(0.28, 0.9, 0.5), v(-(face.W / 2 + 0.12), face.Y, 0), pot, true)
		local sx, sy = turn(1.1, 0, a)
		socket("SpoutSocket", v(rx + sx, ry + sy, 0))
	end

	-- The species' own Bits: each one is a few blocks at most.
	local hx, hz = face.W / 2 + 0.03, face.D / 2 + 0.03
	if bits.Spots then -- freckles on the head's sides and back
		local spot = Pure.darken(body, 0.2)
		add("Spot", v(0.06, 0.42, 0.42), v(hx, face.Y + 0.2, 0.25), spot, true)
		add("Spot", v(0.06, 0.34, 0.34), v(-hx, face.Y - 0.15, -0.15), spot, true)
		add("Spot", v(0.42, 0.42, 0.06), v(0.35, face.Y + 0.05, hz), spot, true)
	end
	if bits.Dots then -- polka dots
		add("Dot", v(0.06, 0.32, 0.32), v(hx, face.Y - 0.2, -0.45), CREAM, false)
		add("Dot", v(0.06, 0.32, 0.32), v(-hx, face.Y + 0.2, 0.55), CREAM, false)
		add("Dot", v(0.32, 0.32, 0.06), v(-0.35, face.Y, hz), CREAM, false)
	end
	if bits.Bell then -- a little golden bell with a ribbon, under the chin
		local y, z = bodyTop - 0.27, -bd / 2 - 0.2
		add("Bell", v(0.38, 0.38, 0.38), v(0, y, z), GOLDEN, true)
		add("BellSlit", v(0.26, 0.05, 0.03), v(0, y - 0.08, z - 0.2), INK_EYE, false)
		add("BellBow", v(0.52, 0.16, 0.14), v(0, y + 0.24, z + 0.02), accent, true)
	end
	if bits.Whiskers then
		for _, side in { 1, -1 } do
			for _, k in { -1, 1 } do
				local at = v(side * (muzzleW / 2 + 0.22), muzzleY + k * 0.07, lower - 0.02)
				add(
					"Whisker",
					v(0.55, 0.05, 0.05),
					at,
					Pure.darken(body, 0.5),
					false,
					{ Rot = v(0, 0, k * side * 0.15) }
				)
			end
		end
	end
	if bits.Butter then -- a pat of butter on the toast
		add("Butter", v(0.8, 0.18, 0.62), v(0.12, T + 0.08, 0.05), BUTTER, true, { Rot = v(0, 0.35, 0) })
	end
	if bits.Cherry then -- a jelly's cherry, on its forehead in front of the ears
		local z = -face.D / 2 + 0.35
		add("Cherry", v(0.42, 0.42, 0.42), v(0, T + 0.2, z), CHERRY, true)
		add("CherryStem", v(0.07, 0.36, 0.07), v(0.05, T + 0.55, z + 0.01), STEM, false, { Rot = v(0, 0, -0.3) })
	end
	if bits.CottonTail then
		add("CottonTail", v(0.5, 0.5, 0.5), v(0, lift + 0.45, bd / 2 + 0.2), CREAM, true)
	end
	if bits.Puddle then -- a slime's puddle round its base
		add(
			"Puddle",
			v(bw + 0.5, 0.1, bd + 0.45),
			v(0, 0.05, 0),
			Pure.tone(body, 0.06),
			true,
			{ Big = true, Clear = 0.1 }
		)
	end
	if bits.Glasses then -- square specs on a see-through plate in front of the eyes
		local w, gh = 2 * (eyeX + 0.36 * es), 0.8 * es
		add("Glasses", v(w, gh, 0.02), v(0, eyeY, eyeFront - 0.13), GLINT, false, {
			Clear = 1,
			Gui = "Glasses",
			Gap = eyeX / w,
			LensW = 0.62 * es / w,
			LensH = 0.7 * es / gh,
		})
	end
	if bits.Syrup and scoop then -- snow-cone syrup: a pink splash down the front, a blue one on top
		add("Syrup", v(0.6, 0.5, 0.05), v(-0.25, scoop.Y + 0.15, scoop.Front - 0.025), SYRUP, false)
		add("Syrup", v(0.55, 0.05, 0.5), v(0.25, scoop.Top + 0.025, 0), SYRUP_BLUE, false)
	end
	if bits.EyeRings then -- an owl's pale face patches round the eyes
		for _, side in { 1, -1 } do
			add("EyeRing", v(0.74 * es, 0.84 * es, 0.04), v(side * eyeX, eyeY, faceZ - 0.02), accent, true)
		end
	end
	if bits.Hem then -- a ghost's hem: teeth along the bottom edge
		local teeth = { { -0.95, -0.8 }, { 0, -0.8 }, { 0.95, -0.8 }, { -0.65, 0.8 }, { 0.65, 0.8 } }
		for _, at in teeth do
			add("Hem", v(0.55, 0.32, 0.55), v(at[1], 0.16, at[2]), body, true)
		end
	end
	if bits.Fluff then -- a fluffy ruff under the chin
		for _, x in { -0.42, 0, 0.42 } do
			local size = if x == 0 then v(0.62, 0.48, 0.34) else v(0.5, 0.4, 0.3)
			add("Fluff", size, v(x, bodyTop - 0.18 - math.abs(x) * 0.2, -bd / 2 - 0.12), CREAM, true)
		end
	end
	if bits.Daisy then -- a daisy tucked on the side of its head
		local at = v(hx, face.Top - 0.38, -face.D / 2 + 0.4)
		for i = 0, 2 do
			add("Petal", v(0.05, 0.17, 0.62), at, CREAM, false, { Rot = v(i * math.pi / 3, 0, 0) })
		end
		add("FlowerMiddle", v(0.07, 0.24, 0.24), v(at.X + 0.02, at.Y, at.Z), GOLDEN, false)
	end

	-- The sockets the client's props go on (see the header).
	socket("HeadSocket", v(0, T, 0))
	for _, side in { 1, -1 } do
		socket("Ear" .. tag(side) .. "Socket", v(side * face.W / 2, face.Y + 0.1, 0), v(side, 0, 0))
	end
	local neckY: number, neck: V3
	if box then
		neckY, neck = mouthY - 0.34, v(bw * 1.3, 0, bd * 1.3)
	elseif shapeName == "Drop" then
		neckY, neck = face.Bottom + 0.05, v(face.W * 1.3, 0, face.D * 1.3)
	else
		neckY, neck = bodyTop - 0.2, v(bw * 1.3, 0, bd * 1.3)
	end
	socket("NeckSocket", v(0, neckY, 0))
	socket("BellySocket", v(0, bellyPos.Y, bellyFront), FRONT)
	socket("BackSocket", v(0, bodyY, bd / 2), BACK)

	return {
		Parts = parts,
		Sockets = sockets,
		Top = T,
		HeadHalf = face.W / 2,
		Neck = neck,
		Brows = if bits.GrumpyBrows then "Grumpy" else "Worried",
		Shape = shapeName,
		Night = night,
	}
end
-- PURE-END

CreatureBuilder.Pure = Pure

local DEFAULT_LOOK: Look = {
	Shape = "Ball",
	Body = "#FF6EC0",
	Accent = "#FFD6EC",
	Ears = "Round",
	Top = "None",
	Extra = "None",
	Scale = 1,
}

-- A hard step at the middle: one half opaque, the other clear. Rotating it sweeps the ring and draws arcs.
local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local badges: { [Model]: Badge } = setmetatable({}, { __mode = "k" }) :: any
local warnedKit: { [string]: boolean } = {}
local warnedBits: { [string]: boolean } = {}

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

local function hex(value: string?, fallback: Color3): Color3
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return fallback
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function v3(t: any): Vector3
	return Vector3.new(t.X, t.Y, t.Z)
end

-- A CFrame at a point, lifted `lift` along the normal, whose front (-Z) faces out along it.
local function facing(p: Vector3, n: Vector3, lift: number): CFrame
	local at = p + n * lift
	local up = if math.abs(n.Y) > 0.95 then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(at, at + n, up)
end

local function corner(gui: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius or 0.5, 0)
	c.Parent = gui
end

-- An Attachment for the client's props (see the header). It rides on the Body part until Core exists.
local function socket(b: Build, name: string, cf: CFrame)
	local anchor = b.Anchor
	if not anchor then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = anchor.CFrame:Inverse() * cf
	a.Parent = anchor
end

-- An arm, wing, flipper or tail: `main` will hang on a Motor6D from Core at `pivot` (unit space).
local function joint(b: Build, key: string, main: BasePart, pivot: CFrame)
	b.Joints[key] = main
	b.Rides[main] = key
	local a = Instance.new("Attachment")
	a.Name = "JointPivot"
	a.CFrame = main.CFrame:Inverse() * pivot
	a.Parent = main
end

------------------------------------------------------------------------------------------------------------------
-- The face drawings: flat pixels on see-through plates (no images, no rounding)
------------------------------------------------------------------------------------------------------------------

local function faceGui(part: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = FACE_PIXELS
	gui.LightInfluence = 0.4
	gui.MaxDistance = FACE_NEAR
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

-- A transparent holder (the whole gui) named `name`, with one square-cornered Frame per cell of a cols x rows grid.
local function pixels(
	parent: Instance,
	name: string,
	cols: number,
	rows: number,
	cells: { { number } },
	color: Color3,
	visible: boolean
): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = visible
	for _, cell in cells do
		local f = Instance.new("Frame")
		f.Name = "Pixel"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.Position = UDim2.fromScale(cell[1] / cols, cell[2] / rows)
		f.Size = UDim2.fromScale((cell[3] or 1) / cols, (cell[4] or 1) / rows)
		f.Parent = holder
	end
	holder.Parent = parent
	return holder
end

-- Closed, contented eyes for sleeping in bed (setMood "Sleep" enables the gui).
local function lidGui(lid: BasePart)
	local gui = faceGui(lid, "LidGui")
	gui.Enabled = false
	local closed = Pure.CLOSED_EYE
	pixels(gui, "Closed", closed.Cols, closed.Rows, closed.Cells, EYE, true)
end

-- Both brows per mood: flat bars over each eye, turned. The creature's right brow is on the plate's left.
local function browGui(brow: BasePart, spec: any, default: string)
	local gui = faceGui(brow, "BrowGui")
	local color = hex(spec.Ink, EYE)
	local gap = if type(spec.Gap) == "number" then spec.Gap else 0.3
	local bar = if type(spec.Bar) == "number" then spec.Bar else 0.3
	for _, mood in Pure.BROW_ORDER do
		local shape = Pure.BROWS[mood]
		local holder = Instance.new("Frame")
		holder.Name = mood
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.Visible = mood == default
		for _, side in { 1, -1 } do
			local f = Instance.new("Frame")
			f.Name = if side > 0 then "BrowR" else "BrowL"
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(0.5 - side * gap, shape.Y)
			f.Size = UDim2.fromScale(bar, 0.42)
			f.Rotation = shape.Turn * side
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color
			f.Parent = holder
		end
		holder.Parent = gui
	end
end

-- The pixel mouth: one drawing per mood (setMood shows one). Sick shows until a mood is set.
local function mouthGui(mouth: BasePart)
	local gui = faceGui(mouth, "MouthGui")
	local grid = Pure.MOUTH
	for _, mood in Pure.MOUTH_ORDER do
		pixels(gui, mood, grid.Cols, grid.Rows, grid[mood], MOUTH, mood == "Sick")
	end
end

-- Square specs: two tinted lenses with a thick rim and a bridge.
local function glassesGui(plate: BasePart, spec: any)
	local gui = faceGui(plate, "GlassesGui")
	local gap = if type(spec.Gap) == "number" then spec.Gap else 0.3
	local w = if type(spec.LensW) == "number" then spec.LensW else 0.36
	local h = if type(spec.LensH) == "number" then spec.LensH else 0.86
	for _, side in { 1, -1 } do
		local lens = Instance.new("Frame")
		lens.Name = "Lens"
		lens.AnchorPoint = Vector2.new(0.5, 0.5)
		lens.Position = UDim2.fromScale(0.5 - side * gap, 0.5)
		lens.Size = UDim2.fromScale(w, h)
		lens.BackgroundColor3 = LENS
		lens.BackgroundTransparency = 0.78
		lens.BorderSizePixel = 0
		local rim = Instance.new("UIStroke")
		rim.Color = GLASS_RIM
		rim.Thickness = 6
		rim.Parent = lens
		lens.Parent = gui
	end
	local bridge = Instance.new("Frame")
	bridge.Name = "Bridge"
	bridge.AnchorPoint = Vector2.new(0.5, 0.5)
	bridge.Position = UDim2.fromScale(0.5, 0.42)
	bridge.Size = UDim2.fromScale(math.max(2 * gap - w, 0.02) + 0.02, 0.08)
	bridge.BackgroundColor3 = GLASS_RIM
	bridge.BorderSizePixel = 0
	bridge.Parent = gui
end

------------------------------------------------------------------------------------------------------------------
-- The placeholder creature: Pure.layout's blocks made real
------------------------------------------------------------------------------------------------------------------

local function makePart(b: Build, spec: any, night: boolean, brows: string)
	local p = Instance.new("Part")
	p.Name = spec.Name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Size = v3(spec.Size)
	local cf = CFrame.new(v3(spec.Pos))
	if spec.Rot then
		cf *= CFrame.Angles(spec.Rot.X, spec.Rot.Y, spec.Rot.Z)
	end
	p.CFrame = cf
	p.Color = hex(spec.Color, WHITE)
	if spec.Studs then
		Studs.apply(p) -- the stud plate: Plastic with studs on its top (World/Studs picks the way)
	else
		Studs.smooth(p) -- SmoothPlastic: no cut-off studs on small blocks
		if spec.Neon and night then
			p.Material = Enum.Material.Neon -- glowing tips at night
		end
	end
	if type(spec.Clear) == "number" then
		p.Transparency = spec.Clear
	end
	if spec.Shadow == false or (type(spec.Clear) == "number" and spec.Clear >= 1) then
		p.CastShadow = false
	end
	p.Parent = b.Model
	if spec.Tint then
		table.insert(b.Tint, p)
	end
	if spec.Big then
		b.Big[p] = true
	end
	if spec.Name == "Body" then
		b.Anchor = p
	end
	if type(spec.Joint) == "string" and spec.Pivot then
		joint(b, spec.Joint, p, CFrame.new(v3(spec.Pivot)))
	elseif type(spec.Ride) == "string" then
		b.Rides[p] = spec.Ride
	end
	if spec.Hand then
		local hand = Instance.new("Attachment")
		hand.Name = "HandSocket"
		hand.CFrame = CFrame.new(v3(spec.Hand)) * CFrame.Angles(0, 0, -(spec.HandTilt or 0))
		hand.Parent = p
	end
	if spec.Gui == "Lid" then
		lidGui(p)
	elseif spec.Gui == "Brow" then
		browGui(p, spec, brows)
	elseif spec.Gui == "Mouth" then
		mouthGui(p)
	elseif spec.Gui == "Glasses" then
		glassesGui(p, spec)
	end
end

local function placeholder(
	look: Look,
	night: boolean,
	scale: number
): (Model, { BasePart }, { [BasePart]: boolean }, Rig)
	local model = Instance.new("Model")
	model.WorldPivot = CFrame.identity -- so ScaleTo scales around the unit origin (the ground under the body)
	local layout = Pure.layout(look, { Night = night, Scale = scale })
	local b: Build = { Model = model, Tint = {}, Big = {}, Anchor = nil, Rides = {}, Joints = {} }
	for _, spec in layout.Parts do
		makePart(b, spec, night, layout.Brows)
	end
	for _, s in layout.Sockets do
		local at = v3(s.Pos)
		socket(b, s.Name, if s.Normal then facing(at, v3(s.Normal), 0) else CFrame.new(at))
	end
	for _, name in look.Bits or {} do
		if not Pure.KNOWN_BITS[name] and not warnedBits[name] then
			warnedBits[name] = true
			warn("[CreatureBuilder] unknown Look.Bits entry " .. tostring(name))
		end
	end
	if layout.Brows == "Grumpy" then
		model:SetAttribute("Brows", "Grumpy")
	end

	if scale ~= 1 then
		model:ScaleTo(scale) -- every part is still anchored, so this is a plain resize around the origin
	end
	model:SetAttribute("BuildScale", scale)
	model:SetAttribute("HeadRadius", layout.HeadHalf * scale)
	model:SetAttribute("NeckSize", v3(layout.Neck) * scale)
	return model, b.Tint, b.Big, { Rides = b.Rides, Joints = b.Joints }
end

------------------------------------------------------------------------------------------------------------------
-- The brother's model (ServerStorage.Creatures.<PatientId>)
------------------------------------------------------------------------------------------------------------------

local function fromKit(patientId: string, scale: number, jitter: number): (Model?, { BasePart }?)
	local folder = ServerStorage:FindFirstChild("Creatures")
	local template = folder and folder:FindFirstChild(patientId)
	if not template then
		return nil, nil
	end
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	elseif template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	else
		if not warnedKit[patientId] then
			warnedKit[patientId] = true
			warn("[CreatureBuilder] Creatures." .. patientId .. " must be a Model or a MeshPart; using the placeholder")
		end
		return nil, nil
	end

	-- Patients move by tweens, so nothing in the model may act on its own: no scripts, no Humanoids.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Humanoid") then
			descendant:Destroy()
		end
	end
	local tint: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			table.insert(tint, descendant)
		end
	end
	if #tint == 0 then
		model:Destroy()
		return nil, nil
	end

	model:PivotTo(CFrame.identity)
	local _, size = model:GetBoundingBox()
	if size.Y < 1 or size.Y > 9 then -- far off the placeholder size: bring it near 3 units tall
		model:ScaleTo(model:GetScale() * (3 * scale / math.max(size.Y, 0.05)))
	elseif jitter ~= 1 then
		model:ScaleTo(model:GetScale() * jitter) -- its own size, give or take this patient's wobble
	end
	return model, tint
end

------------------------------------------------------------------------------------------------------------------
-- Root, Core, joints, sockets, effects and the badge
------------------------------------------------------------------------------------------------------------------

-- Root at the bottom centre: of the body (a placeholder is built round x = z = 0) or of the bounding box (a kit).
local function addRoot(model: Model, centred: boolean): (Part, number, number)
	model:PivotTo(CFrame.identity)
	local box, size = model:GetBoundingBox()
	local bottom = box.Y - size.Y / 2
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * ROOT_SIZE
	root.CFrame = if centred then CFrame.new(0, bottom, 0) else CFrame.new(box.X, bottom, box.Z)
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
	model:PivotTo(CFrame.identity) -- the bottom centre is now the origin
	return root, size.Y, size.Y * 0.5
end

-- Core on Root (PoseJoint), the limbs on their Motor6Ds, everything else welded on, and the sockets moved onto Core.
local function rig(model: Model, root: BasePart, info: Rig?): Part
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.one * ROOT_SIZE
	core.CFrame = root.CFrame
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Massless = true
	core.CollisionGroup = COLLISION_GROUP
	core.Parent = model

	local pose = Instance.new("Motor6D")
	pose.Name = "PoseJoint"
	pose.Part0 = root
	pose.Part1 = core
	pose.Parent = root

	local joints: { [string]: BasePart } = if info then info.Joints else {}
	local rides: { [BasePart]: string } = if info then info.Rides else {}
	for key, main in joints do
		local pivot = main:FindFirstChild("JointPivot")
		if pivot and pivot:IsA("Attachment") then
			local motor = Instance.new("Motor6D")
			motor.Name = key .. "Joint"
			motor.Part0 = core
			motor.Part1 = main
			motor.C0 = core.CFrame:Inverse() * (main.CFrame * pivot.CFrame)
			motor.C1 = pivot.CFrame
			motor.Parent = core
			pivot:Destroy()
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			if descendant ~= core then
				local key = rides[descendant]
				local holder = if key then joints[key] else nil
				if holder ~= descendant then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = holder or core
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end

	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		for _, child in body:GetChildren() do
			if child:IsA("Attachment") and string.sub(child.Name, -6) == "Socket" then
				local world = body.CFrame * child.CFrame
				child.Parent = core
				child.CFrame = core.CFrame:Inverse() * world
			end
		end
	end
	return core
end

-- A kit model has no sockets of its own: guess them from its bounding box (Root at the bottom centre).
local function kitSockets(model: Model, core: BasePart, height: number)
	local _, size = model:GetBoundingBox()
	local w, h, d = size.X, height, size.Z
	local function put(name: string, position: Vector3, normal: Vector3)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = facing(position, normal, 0)
		a.Parent = core
	end
	local front = Vector3.new(0, 0, -1)
	put("FaceSocket", Vector3.new(0, 0.5 * h, -d / 2), front)
	put("NoseSocket", Vector3.new(0, 0.56 * h, -d / 2), front)
	put("BrowSocket", Vector3.new(0, 0.8 * h, -0.4 * d), Vector3.new(0, 0.5, -1).Unit)
	put("HeadSocket", Vector3.new(0, h, 0), Vector3.new(0, 1, 0))
	put("NeckSocket", Vector3.new(0, 0.42 * h, 0), front)
	put("BellySocket", Vector3.new(0, 0.3 * h, -d / 2), front)
	put("BackSocket", Vector3.new(0, 0.45 * h, d / 2), Vector3.new(0, 0, 1))
	for _, side in { -1, 1 } do
		local tag = if side > 0 then "R" else "L"
		put("Eye" .. tag .. "Socket", Vector3.new(side * 0.18 * w, 0.62 * h, -d / 2), front)
		put(
			"Cheek" .. tag .. "Socket",
			Vector3.new(side * 0.3 * w, 0.5 * h, -0.45 * d),
			Vector3.new(side * 0.4, 0, -1).Unit
		)
		put("Ear" .. tag .. "Socket", Vector3.new(side * w / 2, 0.75 * h, 0), Vector3.new(side, 0, 0))
	end
	model:SetAttribute("BuildScale", h / 3)
	model:SetAttribute("HeadRadius", w * 0.35)
	model:SetAttribute("NeckSize", Vector3.new(w * 0.8, 0, d * 0.8))
end

local function sparkleEmitter(name: string, colors: ColorSequence, size: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARKLE_TEXTURE
	e.Color = colors
	e.LightEmission = 0.5 -- half additive: bright, but the candy colour still shows in daylight
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6) })
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(1.5, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.RotSpeed = NumberRange.new(-90, 90)
	return e
end

-- A night creature's own glow: its body colour made rich (saturated, full brightness). A white-ish body glows lilac.
local function glowOf(body: Color3): Color3
	local h, s = body:ToHSV()
	if s < 0.12 then
		return Color3.fromRGB(190, 140, 255)
	end
	return Color3.fromHSV(h, math.max(s, 0.72), 1)
end

local function addEffects(model: Model, root: Part, middle: number, night: boolean, variant: string?, body: Color3)
	local fx = Instance.new("Attachment")
	fx.Name = "FX"
	fx.Position = Vector3.new(0, middle, 0)
	fx.Parent = root

	if night then
		-- Spooky-cute: a rich glow in the creature's own colour, never scary. A Neon pad under its feet (square, like
		-- the rest of it) and a shadow-free PointLight do what a Highlight rim did, at a fraction of the cost (no
		-- Highlights on creatures). It keeps the name GlowRing.
		local color = glowOf(body)
		local glow = Instance.new("PointLight")
		glow.Name = "NightGlow"
		glow.Color = color
		glow.Brightness = 1.8
		glow.Range = 12
		glow.Shadows = false
		glow.Parent = fx

		local extents = model:GetExtentsSize()
		local width = math.max(extents.X, extents.Z, 0.5) * GLOW_RING_WIDTH
		local ring = Instance.new("Part")
		ring.Name = "GlowRing"
		ring.Size = Vector3.new(width, 0.08, width)
		ring.CFrame = root.CFrame * CFrame.new(0, 0.06, 0)
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = GLOW_RING_TRANSPARENCY
		ring.CastShadow = false
		ring.Anchored = false
		ring.Massless = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CollisionGroup = COLLISION_GROUP
		ring.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ring
		weld.Parent = ring
	end

	local healLight = Instance.new("PointLight")
	healLight.Name = "HealLight"
	healLight.Color = HEAL
	healLight.Brightness = 1.6
	healLight.Range = 9
	healLight.Shadows = false
	healLight.Enabled = false
	healLight.Parent = fx

	local heal = sparkleEmitter("Heal", ColorSequence.new(HEAL, HEAL_LIGHT), 0.38, 9)
	heal.EmissionDirection = Enum.NormalId.Top
	heal.SpreadAngle = Vector2.new(45, 45)
	heal.Speed = NumberRange.new(1, 2)
	heal.Acceleration = Vector3.new(0, 1, 0)
	heal.Lifetime = NumberRange.new(1, 1.6)
	heal.Enabled = false
	heal.Parent = fx

	if variant == "Sparkly" then
		-- Rainbow glitter: each speck runs through the candy colours, so the cloud is every colour at once.
		local glitter = sparkleEmitter("Sparkle", RAINBOW, 0.46, 10)
		glitter.LightEmission = 0.7
		glitter.Parent = fx
	elseif variant == "Frosty" then
		local frost = sparkleEmitter("Frost", ColorSequence.new(WHITE, Candy.Cyan), 0.34, 7)
		frost.Speed = NumberRange.new(0.5, 1.2)
		frost.Acceleration = Vector3.new(0, -1.5, 0)
		frost.Lifetime = NumberRange.new(1, 1.8)
		frost.LightEmission = 0.6
		frost.Parent = fx
	elseif variant == "Golden" then
		-- Progression v2: a soft gold shimmer rising off it (Patients turns it on with setEffect "Golden").
		local gold = sparkleEmitter("Golden", ColorSequence.new(GOLD, GOLD_LIGHT), 0.42, 9)
		gold.EmissionDirection = Enum.NormalId.Top
		gold.SpreadAngle = Vector2.new(60, 60)
		gold.Speed = NumberRange.new(1, 2.2)
		gold.LightEmission = 0.7
		gold.Parent = fx
	end
end

-- The performance rules (header): no Highlights, no shadow-casting lights, no shadows from small parts. `source`
-- names a kit model in the warning; the placeholder never has a Highlight.
local warnedHighlight: { [string]: boolean } = {}
local function trimForPerformance(model: Model, source: string)
	local removed = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Highlight") then
			descendant:Destroy()
			removed += 1
		elseif descendant:IsA("Light") then
			descendant.Shadows = false
		elseif descendant:IsA("BasePart") then
			local size = descendant.Size
			if math.max(size.X, size.Y, size.Z) < SHADOW_STUDS then
				descendant.CastShadow = false
			end
		end
	end
	if removed > 0 and not warnedHighlight[source] then
		warnedHighlight[source] = true
		warn(
			"[CreatureBuilder] Removed " .. removed .. " Highlight(s) from " .. source .. " (creatures never use them)"
		)
	end
end

-- Sparkly: the big parts (Pure.layout's Big: the body, head, belly, arms, the half-lids and the stud plate, so they
-- still match) get brighter and a little more saturated; the small bits (ears, tops, wings, tails, feet) take a
-- rainbow colour by height, red-pink on top down to violet at the feet, like a holo sticker. Both stay at world
-- values (no channel near 255). A kit model's parts aren't ours, so all of them count as big (`big` = nil).
local function rainbowTint(tint: { BasePart }, big: { [BasePart]: boolean }?)
	local low, high = math.huge, -math.huge
	for _, part in tint do
		low = math.min(low, part.Position.Y)
		high = math.max(high, part.Position.Y)
	end
	local span = math.max(high - low, 0.01)
	for _, part in tint do
		if big == nil or big[part] then
			local h, s, value = part.Color:ToHSV()
			part.Color = Color3.fromHSV(h, math.min(s + 0.1, 1), math.min(value + 0.1, SPARKLY_VALUE))
		else
			local t = (part.Position.Y - low) / span -- 0 at the bottom, 1 at the top
			part.Color = part.Color:Lerp(Color3.fromHSV((1 - t) * 0.78, 0.72, SPARKLY_VALUE), 0.6)
		end
		part.Reflectance = 0.05
	end
end

local function applyVariant(tint: { BasePart }, variant: string?, big: { [BasePart]: boolean }?)
	if variant == "Frosty" then
		for _, part in tint do
			part.Color = part.Color:Lerp(ICE, 0.45)
			part.Reflectance = 0.1
		end
	elseif variant == "Sparkly" then
		rainbowTint(tint, big)
	elseif variant == "Golden" then
		for _, part in tint do
			part.Color = part.Color:Lerp(GOLD, 0.55)
			part.Reflectance = 0.18
		end
	end
end

local function circle(parent: Instance, name: string, size: number, position: UDim2, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	corner(f)
	f.Parent = parent
	return f
end

local function emoji(parent: Instance, name: string, text: string, size: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.52)
	l.Size = UDim2.fromScale(size, size)
	l.BackgroundTransparency = 1
	l.Font = Palette.BodyFont
	l.TextScaled = true
	l.TextColor3 = Palette.Ink
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- A plain see-through frame centred in its parent, `size` of it.
local function holder(parent: Instance, name: string, size: number, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- A corner chip: a candy ring with a thick dark outline, a white middle and an emoji in it.
local function chip(parent: Instance, name: string, size: number, position: UDim2, ring: Color3, icon: string): Frame
	local root = circle(parent, name, size, position, ring, 7)
	Palette.outlineShape(root, 3)
	local inner = circle(root, "Inner", 0.74, UDim2.fromScale(0.5, 0.5), WHITE, 1)
	emoji(inner, name .. "Icon", icon, 0.8, 2)
	return root
end

-- One half of the ring: a clip frame showing half of a full circle whose gradient decides how much shows.
local function ringHalf(parent: Instance, name: string, right: boolean): (Frame, UIGradient)
	local clip = Instance.new("Frame")
	clip.Name = name
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromScale(if right then 0.5 else 0, 0)
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.ZIndex = 2
	clip.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = RING_START
	fill.Position = UDim2.fromScale(if right then -1 else 0, 0)
	fill.Size = UDim2.fromScale(2, 1)
	fill.ZIndex = 2
	corner(fill)
	fill.Parent = clip
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = HALF
	gradient.Parent = fill
	return fill, gradient
end

local function makeBadge(
	anchor: Attachment,
	ailmentIcon: string,
	itemIcon: string,
	ring: Color3,
	sticker: string?,
	stickerRing: Color3
): Badge
	local centre = UDim2.fromScale(0.5, 0.5)
	local gui = Instance.new("BillboardGui")
	gui.Name = "IconGui"
	gui.Size = UDim2.fromScale(BADGE_STUDS, BADGE_STUDS) -- studs: big enough to read on a phone from the counter
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 75
	gui.DistanceLowerLimit = NEAR_STUDS
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- From the outside in: a thick dark rim, the patience ring, the station's candy ring, then a white disc with the
	-- ailment. The rim is a dark circle rather than a stroke, so it stays chunky at every distance.
	local face = holder(gui, "Face", BADGE_FACE, 1)
	local rim = circle(face, "Outline", 1, centre, Palette.Outline, 1)
	circle(face, "Track", 0.9, centre, TRACK, 2)
	local ringFrame = holder(face, "Ring", 0.9, 3)
	local fillLeft, gradLeft = ringHalf(ringFrame, "RingLeft", false)
	local fillRight, gradRight = ringHalf(ringFrame, "RingRight", true)
	local stationRing = circle(face, "StationRing", 0.76, centre, ring, 4) -- the treating station's colour
	Palette.outlineShape(stationRing, 2.5)
	local disc = circle(face, "Disc", 0.6, centre, WHITE, 5)
	Palette.outlineShape(disc, 2)
	local icon = emoji(face, "Icon", ailmentIcon, 0.5, 6)

	local need = chip(face, "Need", 0.4, UDim2.fromScale(0.86, 0.86), ring, itemIcon)
	local star = chip(face, "Star", 0.44, UDim2.fromScale(0.14, 0.14), Candy.Yellow, "⭐")
	star.Visible = false
	local stickerFrame = chip(face, "Sticker", 0.4, UDim2.fromScale(0.86, 0.14), stickerRing, sticker or "")
	stickerFrame.Visible = sticker ~= nil
	-- Progression v2: the department chip (left edge, clear of the recipe row and the corners) and the 🚑/🚁 chip
	-- (the Visitor star's corner: an urgent patient is never Today's Visitor). Hidden until set.
	local deptFrame = chip(face, "Dept", 0.34, UDim2.fromScale(0.08, 0.5), DEPT_RING, "")
	deptFrame.Visible = false
	local urgentFrame = chip(face, "Urgent", 0.44, UDim2.fromScale(0.14, 0.14), Candy.Orange, "")
	urgentFrame.Visible = false
	-- A 2-3 item recipe's chips (setRecipe fills it in); hidden until a recipe has more than one item.
	local recipe = holder(face, "Recipe", 1, 7)
	recipe.Visible = false
	gui.Parent = anchor

	-- A regular's speech bubble: an emote and 6 words or fewer, in chunky outlined letters on a candy bubble with a
	-- dark outline and a dark lip underneath. Inset from the gui's edge so the outlines always show whole.
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "BubbleGui"
	bubble.Size = UDim2.fromScale(8, 2.6)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	bubble.LightInfluence = 0
	bubble.MaxDistance = 60
	bubble.DistanceLowerLimit = NEAR_STUDS
	bubble.Enabled = false
	bubble.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0)
	shadow.Position = UDim2.fromScale(0.5, 0.1)
	shadow.Size = UDim2.fromScale(0.96, 0.68)
	shadow.BackgroundColor3 = Palette.Outline
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	corner(shadow, 0.45)
	shadow.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.76)
	tail.Size = UDim2.fromScale(0.07, 0.215) -- a square: 0.56 x 0.56 studs
	tail.Rotation = 45
	tail.BackgroundColor3 = BUBBLE
	tail.BorderSizePixel = 0
	tail.ZIndex = 2
	Palette.outlineShape(tail, 3)
	tail.Parent = bubble
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.04)
	body.Size = UDim2.fromScale(0.96, 0.68)
	body.BackgroundColor3 = BUBBLE
	body.BorderSizePixel = 0
	body.ZIndex = 3
	corner(body, 0.45)
	Palette.outlineShape(body, 3)
	body.Parent = bubble
	local emote = emoji(body, "Emote", "", 0.8, 4)
	emote.SizeConstraint = Enum.SizeConstraint.RelativeYY
	emote.AnchorPoint = Vector2.new(0, 0.5)
	emote.Position = UDim2.fromScale(0.03, 0.5)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.fromScale(0.25, 0.5)
	text.Size = UDim2.fromScale(0.71, 0.72)
	text.BackgroundTransparency = 1
	text.Font = Palette.DisplayFont
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = WHITE
	text.Text = ""
	text.ZIndex = 4
	Palette.outlineText(text)
	text.Parent = body
	bubble.Parent = anchor

	local badge: Badge = {
		Gui = gui,
		Icon = icon,
		Need = need,
		Star = star,
		Sticker = stickerFrame,
		Dept = deptFrame,
		Urgent = urgentFrame,
		Rim = rim,
		FillLeft = fillLeft,
		FillRight = fillRight,
		GradLeft = gradLeft,
		GradRight = gradRight,
		Bubble = bubble,
		BubbleEmote = emote,
		BubbleText = text,
	}
	return badge
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function CreatureBuilder.build(patientId: string, variant: string?): Model
	local entry = PatientsData[patientId]
	local regular = Regulars[patientId]
	local look: Look = if entry then entry.Look elseif regular then regular.Look else DEFAULT_LOOK
	-- Night patients glow; so do Night-wing regulars (they only visit at night).
	local night = (entry ~= nil and entry.Night == true) or (regular ~= nil and regular.Wing == "Night")
	local variantData = if variant then Variants[variant] else nil
	-- Its size: the species' own, player-sized, give or take this patient's wobble (Logic/CreatureSize).
	local roll = math.random()
	local scale = CreatureSize.scale(look.Scale, Config, roll)

	local kitModel, kitTint = fromKit(patientId, scale, CreatureSize.jitter(roll, Config))
	local model: Model, tint: { BasePart }, big: { [BasePart]: boolean }?, info: Rig?
	if kitModel and kitTint then
		model, tint = kitModel, kitTint
	else
		model, tint, big, info = placeholder(look, night, scale)
	end
	applyVariant(tint, variant, big)

	local root, height, middle = addRoot(model, info ~= nil)
	local core = rig(model, root, info)
	if not info then
		kitSockets(model, core, height)
	end
	addEffects(model, root, middle, night, variant, hex(look.Body, WHITE))

	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, height + 0.25, 0)
	anchor.Parent = root
	badges[model] = makeBadge(
		anchor,
		"❔", -- a species has no case of its own: Patients sets the symptom, then the case after the exam
		"",
		DEFAULT_STATION,
		if variantData then variantData.Icon else nil,
		if variant then STICKER_RING[variant] or WHITE else WHITE
	)

	trimForPerformance(model, if kitModel then "Creatures." .. patientId else "the placeholder")
	model.Name = patientId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never half a creature
	model:SetAttribute("PatientId", patientId)
	model:AddTag(CREATURE_TAG) -- Feel/CreatureActing acts its ailment on the Motor6Ds
	model:AddTag(CreatureBuilder.MOTION_TAG) -- its hops are drawn on the clients (Feel/CreatureMotion)
	return model
end

-- Not tagged: the caller decides how it moves (plot nurses use the motion attributes and the tag; belt riders
-- follow the belt formula instead, build plan §B4).
function CreatureBuilder.buildLook(look: any, name: string?): Model
	local recipe: Look = if type(look) == "table" then look else DEFAULT_LOOK
	-- The species' own size, player-sized like the patients, with no wobble (every copy of a nurse is the same).
	local scale = CreatureSize.scale(recipe.Scale, Config)
	local model, _, _, info = placeholder(recipe, false, scale)
	local root, height = addRoot(model, true)
	rig(model, root, info)
	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, height + 0.25, 0)
	anchor.Parent = root
	trimForPerformance(model, "the placeholder")
	model.Name = name or "Creature"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CreatureBuilder.setMood(model, "Happy") -- a nurse (or the mascot) is never sick
	return model
end

-- One chip's look: the item's icon on its station's colour; a given item dims and gets a ✅ (if the chip has one).
local function paintChip(chipFrame: GuiObject, itemId: any, given: boolean)
	local item = if type(itemId) == "string" then rawget(Items :: any, itemId) else nil -- never `Order`
	chipFrame.BackgroundColor3 = if item then ITEM_RING[itemId] or DEFAULT_STATION else DEFAULT_STATION
	local icon = chipFrame:FindFirstChild(chipFrame.Name .. "Icon", true)
	if icon and icon:IsA("TextLabel") then
		icon.Text = if item then item.Icon else ""
		icon.TextTransparency = if given then 0.55 else 0
	end
	local inner = chipFrame:FindFirstChild("Inner")
	if inner and inner:IsA("GuiObject") then
		inner.BackgroundTransparency = if given then 0.3 else 0
	end
	local tick = chipFrame:FindFirstChild("Tick")
	if tick and tick:IsA("GuiObject") then
		tick.Visible = given
	end
end

local function recipeChip(row: Frame, name: string): Frame
	local found = row:FindFirstChild(name)
	if found and found:IsA("Frame") then
		return found
	end
	local made = chip(row, name, 0.34, UDim2.fromScale(0.5, RECIPE_Y), DEFAULT_STATION, "")
	local tick = emoji(made, "Tick", TICK, 0.6, 9)
	tick.Position = UDim2.fromScale(0.84, 0.16)
	tick.Visible = false
	return made
end

function CreatureBuilder.setRecipe(badge: Badge, items: { string }, done: { boolean })
	local list: { any } = if type(items) == "table" then items else {}
	local given: { any } = if type(done) == "table" then done else {}
	local count = math.min(#list, RECIPE_MAX)
	local nextIndex: number? = nil
	for index = 1, count do
		if given[index] ~= true then
			nextIndex = index
			break
		end
	end

	local face = badge.Gui:FindFirstChild("Face")
	local found = face and face:FindFirstChild("Recipe")
	local row: Frame? = if found and found:IsA("Frame") then found else nil
	local need = badge.Need
	if count <= 1 or not row then
		-- One item (or none): the Need chip shows what's still missing, as it always has.
		if row then
			row.Visible = false
		end
		paintChip(need, if nextIndex then list[nextIndex] else nil, false)
		need.Visible = nextIndex ~= nil
		return
	end

	need.Visible = false
	row.Visible = nextIndex ~= nil -- all given: the treat flow takes the badge over
	local spots = recipeLayout(count, nextIndex)
	for index = 1, RECIPE_MAX do
		local name = "Item" .. index
		local spot = spots[index]
		if spot then
			local chipFrame = recipeChip(row, name)
			chipFrame.Position = UDim2.fromScale(spot.X, RECIPE_Y)
			chipFrame.Size = UDim2.fromScale(spot.Size, spot.Size)
			paintChip(chipFrame, list[index], given[index] == true)
			chipFrame.Visible = true
		else
			local extra = row:FindFirstChild(name)
			if extra and extra:IsA("GuiObject") then
				extra.Visible = false
			end
		end
	end
end

-- A kit Model (cloned, scripts removed, every part anchored, its face looking at -Z) gets the patients' rig: Root at
-- the bottom centre of its bounding box, Core on Root.PoseJoint with every part welded to it, and sockets guessed
-- from the box. Pivoted at the origin; returns the model.
function CreatureBuilder.rigKit(model: Model): Model
	local root, height = addRoot(model, false)
	local core = rig(model, root, nil)
	kitSockets(model, core, height)
	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, height + 0.25, 0)
	anchor.Parent = root
	trimForPerformance(model, model.Name)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

function CreatureBuilder.badge(model: Model): Badge?
	return badges[model]
end

-- A chip's emoji (chip() names it "<chip name>Icon").
local function chipIcon(chipFrame: Frame, text: string)
	local label = chipFrame:FindFirstChild(chipFrame.Name .. "Icon", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Progression v2: the department chip (Data/Departments icon); nil, "" or an unknown id hides it.
function CreatureBuilder.setDept(badge: Badge, deptId: string?)
	local dept = if type(deptId) == "string" and deptId ~= "" then rawget(Departments :: any, deptId) else nil
	if type(dept) == "table" and type(dept.Icon) == "string" then
		chipIcon(badge.Dept, dept.Icon)
		badge.Dept.BackgroundColor3 = DEPT_RINGS[deptId :: string] or DEPT_RING
		badge.Dept.Visible = true
	else
		badge.Dept.Visible = false
	end
end

-- Progression v2: an urgent patient's 🚑 / 🚁 chip and coloured rim; anything else puts the plain badge back.
function CreatureBuilder.setUrgent(badge: Badge, urgent: string?)
	local icon = urgentIcon(urgent)
	local ring = if icon and type(urgent) == "string" then URGENT_RING[urgent] else nil
	if icon and ring then
		chipIcon(badge.Urgent, icon)
		badge.Urgent.BackgroundColor3 = ring
		badge.Urgent.Visible = true
		badge.Star.Visible = false
		badge.Rim.BackgroundColor3 = ring
	else
		badge.Urgent.Visible = false
		badge.Rim.BackgroundColor3 = Palette.Outline
	end
end

-- The ring around the badge: `fraction` of a full circle, clockwise from 12 o'clock.
function CreatureBuilder.setRing(badge: Badge, fraction: number, color: Color3)
	local degrees = math.clamp(fraction, 0, 1) * 360
	badge.GradRight.Rotation = math.clamp(degrees, 0, 180)
	badge.GradLeft.Rotation = math.clamp(degrees, 180, 360)
	badge.FillRight.BackgroundColor3 = color
	badge.FillLeft.BackgroundColor3 = color
end

-- Shows the one drawing in `gui` named `shape` and hides its other drawings.
local function showOnly(part: Instance, guiName: string, shape: string)
	local gui = part:FindFirstChild(guiName)
	if gui then
		for _, face in gui:GetChildren() do
			if face:IsA("GuiObject") then
				face.Visible = face.Name == shape
			end
		end
	end
end

-- "Sick" (droopy half-lids, a little o, worried brows) | "Happy" (a wide "w", raised brows) | "Sad" (a frown, sad
-- brows) | "Sleep" (eyes closed, a sleepy smile). A grumpy species (attribute Brows = "Grumpy") frowns its brows
-- while sick. The mouth and brows are pixel drawings (MouthGui, BrowGui), the half-lids real blocks (EyeLid). A kit
-- model without these face parts just ignores it.
function CreatureBuilder.setMood(model: Model, mood: string)
	local sleeping = mood == "Sleep"
	local sick = mood == "Sick"
	local mouthShape = if sleeping then "Smile" else mood
	local browShape = "Happy"
	if sick then
		browShape = if model:GetAttribute("Brows") == "Grumpy" then "Grumpy" else "Worried"
	elseif mood == "Sad" then
		browShape = "Sad"
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local name = child.Name
			if name == "Eye" or name == "EyeShine" or name == "EyeTint" then
				child.Transparency = if sleeping then 1 else 0
			elseif name == "EyeLid" then
				child.Transparency = if sick then 0 else 1
			elseif name == "Lid" then
				local gui = child:FindFirstChild("LidGui")
				if gui and gui:IsA("SurfaceGui") then
					gui.Enabled = sleeping
				end
			elseif name == "Mouth" then
				showOnly(child, "MouthGui", mouthShape)
			elseif name == "Brow" then
				showOnly(child, "BrowGui", browShape)
			end
		end
	end
end

-- Turns a light or emitter under Root.FX on or off (e.g. "Heal" and "HealLight" while recovering).
function CreatureBuilder.setEffect(model: Model, name: string, on: boolean)
	local root = model.PrimaryPart
	local fx = root and root:FindFirstChild("FX")
	local effect = fx and fx:FindFirstChild(name)
	if effect and (effect:IsA("ParticleEmitter") or effect:IsA("Light")) then
		effect.Enabled = on
	end
end

-- A short burst at a spot, on its own Attachment in Terrain so it plays out after the creature is gone.
-- Emitters are switched on briefly instead of Emit(), which doesn't replicate from the server.
function CreatureBuilder.effectAt(position: Vector3, kind: string)
	local emitters: { ParticleEmitter } = {}
	if kind == "Puff" then
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "Puff"
		puff.Texture = SMOKE_TEXTURE
		puff.Color = ColorSequence.new(SAD_PUFF, Color3.fromRGB(214, 222, 255))
		puff.LightEmission = 0.15
		puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) })
		puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		puff.Rate = 70
		puff.Lifetime = NumberRange.new(0.7, 1)
		puff.Speed = NumberRange.new(2, 4)
		puff.SpreadAngle = Vector2.new(180, 180)
		puff.Drag = 4
		puff.Rotation = NumberRange.new(0, 360)
		puff.RotSpeed = NumberRange.new(-60, 60)
		table.insert(emitters, puff)
	elseif kind == "Cure" then
		-- Candy confetti: one emitter per colour, so every speck keeps its own colour.
		for _, color in CONFETTI do
			local confetti = sparkleEmitter("Cure", ColorSequence.new(color, lighten(color, 0.35)), 0.6, 26)
			confetti.EmissionDirection = Enum.NormalId.Top
			confetti.SpreadAngle = Vector2.new(70, 70)
			confetti.Speed = NumberRange.new(7, 11)
			confetti.Acceleration = Vector3.new(0, -10, 0)
			confetti.Lifetime = NumberRange.new(0.5, 0.9)
			table.insert(emitters, confetti)
		end
	else -- "Pop"
		local pop = sparkleEmitter("Pop", ColorSequence.new(Candy.Yellow, Candy.Pink), 0.45, 90)
		pop.Speed = NumberRange.new(5, 8)
		pop.Drag = 4
		pop.Lifetime = NumberRange.new(0.35, 0.6)
		table.insert(emitters, pop)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PatientFX"
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	for _, emitter in emitters do
		emitter.Parent = attachment
	end
	task.delay(0.18, function()
		for _, emitter in emitters do
			emitter.Enabled = false
		end
	end)
	task.delay(2.5, function()
		attachment:Destroy()
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Creature motion: attributes the clients draw (build plan §B4). Setting an attribute to the value it already has
-- sends nothing, so most hops in a walk (same size, same height) send just HopFrom, HopTo and HopAt.
------------------------------------------------------------------------------------------------------------------

CreatureBuilder.MOTION_TAG = "CreatureMotion"

local SCALE_STYLES: { [string]: boolean } = { Back = true, Sine = true, Quad = true }

-- One hop from `from` to `to` over `seconds`: `height` studs up at the top, `spin` radians of turn on the way (a
-- happy spin), `lean` radians forward at the top. The caller waits `seconds`, then writes Root.CFrame = to once.
function CreatureBuilder.hop(
	model: Model,
	from: CFrame,
	to: CFrame,
	seconds: number,
	height: number,
	spin: number?,
	lean: number?
)
	model:SetAttribute("HopFrom", from)
	model:SetAttribute("HopTo", to)
	model:SetAttribute("HopSeconds", math.max(seconds, 0))
	model:SetAttribute("HopHeight", height)
	model:SetAttribute("HopSpin", spin or 0)
	model:SetAttribute("HopLean", lean or 0)
	model:SetAttribute("HopAt", Workspace:GetServerTimeNow()) -- last: a new HopAt tells the clients to read the set
end

-- The wrong-item head-shake (0.55 s), on top of whatever else it's doing.
function CreatureBuilder.shake(model: Model)
	model:SetAttribute("ShakeAt", Workspace:GetServerTimeNow())
end

-- A droop over everything else, until it's set back to 0.
function CreatureBuilder.tilt(model: Model, radians: number)
	model:SetAttribute("Tilt", radians)
end

-- Grow or shrink from `from` to `to` over `seconds` (style "Back" | "Sine" | "Quad", direction "In" | "Out"). The
-- caller writes the end scale once when it's over (Model:ScaleTo(to)).
function CreatureBuilder.scale(
	model: Model,
	from: number,
	to: number,
	seconds: number,
	style: string,
	direction: string
)
	model:SetAttribute("ScaleFrom", from)
	model:SetAttribute("ScaleTo", to)
	model:SetAttribute("ScaleSeconds", math.max(seconds, 0))
	model:SetAttribute("ScaleStyle", if SCALE_STYLES[style] then style else "Quad")
	model:SetAttribute("ScaleDir", if direction == "In" then "In" else "Out")
	model:SetAttribute("ScaleAt", Workspace:GetServerTimeNow()) -- last, like HopAt
end

function CreatureBuilder.start() end

return CreatureBuilder
