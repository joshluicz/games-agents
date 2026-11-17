--!strict
-- CreatureActing: every patient acts out what's wrong with it, with props, and asks for attention when it has waited
-- long (Data/CaseActing, by case). Joshua, 2026-11-16: "they should have animations corresponding to their illness or
-- need for attention. it should be visible with perhaps props. but not gory". Client only and purely visual.
--
-- How it works. CreatureBuilder tags every creature "ClinicCreature" and hangs its body on Root.PoseJoint, its arms
-- (or wings, flippers) on Core.ArmRJoint / ArmLJoint and its tail on Core.TailJoint. This module sets those
-- Motor6Ds' Transform each frame on this client only (Transform never replicates), so the body leans, hops, shivers
-- and waves while the server keeps moving Root. It never writes Root.CFrame. The server only sets attributes on the
-- patient Model (Server/Patients, the Real Clinic visit): Case (only once the exam reveals it), Acting (the CaseId the
-- creature acts out from the start), Symptom (its bubble), State and PatienceFraction (0..1, in 0.05 steps). The
-- acting is CaseActing[Case], else CaseActing[Acting], else the case whose Bubble is the Symptom (the bubble already
-- says it, so acting it out gives nothing away), else CaseActing.Default. A State is played as a phase (PHASES):
--   Arriving   (Arriving, ToBay)            its case's props (Feel/CreatureProps) and a beat every few seconds: a
--   Waiting    (Waiting, AtBay, Planned)    cough, a sniffle, a shiver, a dizzy sway with circling stars...
--                                           Waiting with patience at or under CaseActing.Attention.Wave: a wave now
--                                           and then; at or under Alert: both arms, a bounce and a "!" beside its
--                                           head, and its beats come sooner
--   Treating   (Examining, Treating)        a mini-game is on it: it holds still and only breathes, its props stay
--                                           on, and it acts again when it goes back to waiting for its next step
--   Treated    (Done)                       the props pop off with a sparkle, the colours come back, arms up in relief
--   Recovering (ToWard, Recovering)         slow sleepy breathing
--   Cured      (Leaving after its           a happy wave with both arms, a wagging tail and candy sparkles (the
--              treatment)                   server does the hop)
--   Calm       (Leaving before it)          the props go quietly (it's going home with no sad penalty)
--   Sad        (Sad)                        arms droop and it hangs its head (the server does the puff)
-- Seated (the model's Seated attribute: the server sat it on a waiting-room seat, Logic/CreatureSize.seatFit) is
-- played on top of any phase: it settles into the sit over SIT.EaseSeconds (and out of it as it gets up) with a
-- tiny recline and its tail curled up over its back, off the chair back and the wall; a ghost stops hovering and
-- rests on the seat. It breathes and acts its ailment as ever, and never drifts: Root is the server's.
-- Only creatures within NEAR_STUDS of the camera act; the rest stand still and cost nothing. Calm effects (the
-- ReduceEffects attribute, or the device's Reduced Motion: Kit.reducedMotion()) make every motion small and slow, with
-- no shivering, no circling stars and no bounce, and fewer particles.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local DataFolder = Shared:WaitForChild("Data")
local CaseActing = require(DataFolder:WaitForChild("CaseActing"))
local Cases = require(DataFolder:WaitForChild("Cases"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local CreatureSize = require(Shared:WaitForChild("Logic"):WaitForChild("CreatureSize"))
local Props = require(script.Parent:WaitForChild("CreatureProps"))

local CreatureActing = {}

type Acting = CaseActing.Acting

-- The server's visit states (Server/Patients) as this module's acting phases (the header). "Leaving" is decided by
-- the phase before it (phaseOf); anything unknown acts as Arriving.
local PHASES: { [string]: string } = {
	Arriving = "Arriving",
	ToBay = "Arriving",
	Waiting = "Waiting",
	AtBay = "Waiting",
	Planned = "Waiting",
	Examining = "Treating",
	Treating = "Treating",
	Done = "Treated",
	Treated = "Treated",
	ToWard = "Recovering",
	Recovering = "Recovering",
	Cured = "Cured",
	Sad = "Sad",
}

local function phaseOf(raw: any, previous: string): string
	if raw == "Leaving" then
		local happy = previous == "Treated" or previous == "Recovering" or previous == "Cured"
		return if happy then "Cured" else "Calm"
	end
	return if type(raw) == "string" and PHASES[raw] then PHASES[raw] else "Arriving"
end

-- Before the exam a patient shows only its symptom: the case whose bubble that is.
local BY_BUBBLE: { [string]: string } = {}
for _, caseId in Cases.ORDER do
	local case = rawget(Cases :: any, caseId)
	if type(case) == "table" and type(case.Bubble) == "string" then
		BY_BUBBLE[case.Bubble] = caseId
	end
end

local function actingOf(model: Model): Acting
	local case = model:GetAttribute("Case")
	if type(case) ~= "string" or case == "" then
		case = model:GetAttribute("Acting") -- the server's own pick for the acting, from the start
	end
	if type(case) ~= "string" or case == "" then
		local symptom = model:GetAttribute("Symptom")
		case = if type(symptom) == "string" then BY_BUBBLE[symptom] else nil
	end
	local acting = if type(case) == "string" then rawget(CaseActing :: any, case) else nil
	return if type(acting) == "table" then acting else CaseActing.Default
end

type Creature = {
	Model: Model,
	Root: BasePart,
	Pose: Motor6D,
	ArmR: Motor6D?,
	ArmL: Motor6D?,
	Tail: Motor6D?,
	Ring: BasePart?, -- a night creature's GlowRing pad (Server/CreatureBuilder): hidden while it sits
	RingHidden: number, -- the pad's LocalTransparencyModifier now
	Unit: number,
	Acting: Acting,
	Seconds: number, -- how long one beat of its motion lasts
	State: string,
	Patience: number,
	Props: Props.Kit?,
	Seed: number,
	Ghost: boolean, -- a floaty night creature with no feet: it hovers a little
	Near: boolean,
	NextCheck: number,
	Still: boolean, -- far away: its joints are at rest
	NextBeat: number,
	Beat: number?, -- when the current beat started
	Fired: { [string]: boolean }, -- bursts already fired this beat
	NextWave: number,
	Wave: number?, -- when the current wave started
	WaveBoth: boolean,
	Since: number, -- when State last changed
	Sit: number, -- 0 standing .. 1 sitting: eases toward the Seated attribute (CreatureSize.sitEase)
	Stamp: number, -- when it last acted (the sit eases by the time since)
	Connections: { RBXScriptConnection },
}

local TAG = "ClinicCreature" -- CreatureBuilder.CREATURE_TAG
local ROOT_SIZE = 0.2 -- CreatureBuilder.ROOT_SIZE: Root.Size / ROOT_SIZE is the pop-in scale
local NEAR_STUDS = 120
local CHECK_SECONDS = 0.3
local CALM = 0.35 -- calm effects: motion this big
local WAVE_SECONDS = 1.5
local ALERT_WAVE_SECONDS = 1.7
local RELIEF_SECONDS = 0.9
local JOY_SECONDS = 2

-- How long one beat of each motion lasts (CaseActing.Vocabulary.Motions).
local BEAT_SECONDS: { [string]: number } = {
	Hiccup = 0.5,
	Sneeze = 1.6,
	Cough = 1.15,
	Dizzy = 1.3,
	Sniffle = 1.8,
	Droop = 2.6,
	Stuck = 1.5,
	ShakeOff = 0.9,
	Shiver = 0.8,
	NoseRub = 1.7,
}

local player = Players.LocalPlayer
local creatures: { [Model]: Creature } = {}
local count = 0
local stepConnection: RBXScriptConnection? = nil
local rng = Random.new()

local IDENTITY = CFrame.identity
local TAU = math.pi * 2

------------------------------------------------------------------------------------------------------------------
-- Little curves
------------------------------------------------------------------------------------------------------------------

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	local t = clamp01(x)
	return t * t * (3 - 2 * t)
end

-- 0 -> 1 -> 0 over `d` seconds.
local function pulse(t: number, d: number): number
	if t < 0 or t > d then
		return 0
	end
	return math.sin(math.pi * t / d)
end

-- Up over [a, b], held, down over [c, d].
local function hold(t: number, a: number, b: number, c: number, d: number): number
	if t <= a or t >= d then
		return 0
	elseif t < b then
		return smooth((t - a) / (b - a))
	elseif t <= c then
		return 1
	end
	return 1 - smooth((t - c) / (d - c))
end

local function calm(): boolean
	local value = player:GetAttribute("ReduceEffects")
	if value == nil then
		return Kit.reducedMotion()
	end
	return value == true
end

------------------------------------------------------------------------------------------------------------------
-- One frame of acting
------------------------------------------------------------------------------------------------------------------

type Pose = { Body: CFrame, R: CFrame, L: CFrame, Tail: CFrame }

local function rest(c: Creature): Pose
	local kit = c.Props
	local holding = kit ~= nil and kit.Live and kit.Holds.R == true
	return {
		Body = IDENTITY,
		R = if holding then CFrame.Angles(Props.HOLD_PITCH, 0, 0) else IDENTITY,
		L = IDENTITY,
		Tail = IDENTITY,
	}
end

-- Translation helper: units -> studs at the creature's current size.
local function lift(u: number, x: number, y: number, z: number): CFrame
	return CFrame.new(x * u, y * u, z * u)
end

-- The ailment's continuous idle motion (between and under beats).
local function idle(c: Creature, p: Pose, now: number, u: number, k: number, quiet: boolean)
	local motion = c.Acting.Motion
	local t = now + c.Seed
	if motion == "Dizzy" then
		local w = TAU * (if quiet then 0.3 else 0.5)
		p.Body *= CFrame.Angles(0.07 * k * math.sin(w * t), 0, 0.07 * k * math.cos(w * t))
	elseif motion == "Sniffle" then
		p.Body *= CFrame.Angles(-0.04, 0, 0) -- a sad little lean
	elseif motion == "Droop" then
		p.Body *= CFrame.Angles(-0.06 - 0.03 * k * math.sin(TAU * 0.25 * t), 0, 0)
		p.R *= CFrame.Angles(0, 0, -0.1)
		p.L *= CFrame.Angles(0, 0, 0.1)
	elseif motion == "Shiver" or motion == "NoseRub" then
		local amount = if motion == "Shiver" then 1 else 0.5
		if quiet then
			p.Body *= CFrame.Angles(0, 0, 0.012 * amount * math.sin(TAU * 0.8 * t))
		else
			local envelope = 0.55 + 0.45 * math.sin(TAU * 0.25 * t) ^ 2
			local jiggle = math.sin(TAU * 9 * t)
			p.Body *= lift(u, 0.02 * amount * jiggle * envelope, 0, 0) * CFrame.Angles(
				0,
				0,
				0.025 * amount * math.sin(TAU * 9 * t + 1.3) * envelope
			)
		end
		if motion == "Shiver" then -- hugging itself to keep warm
			p.R = CFrame.Angles(0.7, 0, -0.45)
			p.L = CFrame.Angles(0.7, 0, 0.45)
		end
	end
end

-- One beat of the ailment, `t` seconds in. Fires its bursts once and sets the face.
local function beat(c: Creature, p: Pose, t: number, u: number, k: number, quiet: boolean)
	local kit = c.Props
	local motion = c.Acting.Motion
	local main = c.Acting.Face -- the data's face for the peak of the beat (nil: keep the sick "o")
	local face: string? = nil
	local squint = false -- when the eyes would squeeze; the data's Squint says whether they do
	local function fire(name: string, at: number, amount: number)
		if t >= at and not c.Fired[name .. at] then
			c.Fired[name .. at] = true
			if kit and kit.Live then
				Props.burst(kit, name, if quiet then math.ceil(amount * 0.5) else amount)
			end
		end
	end
	if motion == "Hiccup" then
		local hop = pulse(t, 0.36)
		p.Body *= lift(u, 0, 0.2 * hop * k, 0) * CFrame.Angles(0.1 * hop * k, 0, 0)
		p.R *= CFrame.Angles(0, 0, 0.35 * hop)
		p.L *= CFrame.Angles(0, 0, -0.35 * hop)
		local glass = kit and kit.Motors.Glass
		if glass then
			glass.Transform = CFrame.Angles(0.25 * hop * k, 0, 0)
		end
		face = if t < 0.32 then main else nil
		fire("Bubbles", 0, 2)
		fire("Steam", 0, 3)
	elseif motion == "Sneeze" then
		local pitch: number
		if t < 0.7 then
			pitch = 0.2 * smooth(t / 0.7)
		elseif t < 0.86 then
			pitch = 0.2 - 0.5 * smooth((t - 0.7) / 0.16)
		else
			pitch = -0.3 * (1 - smooth((t - 0.86) / 0.7))
		end
		p.Body *= lift(u, 0, 0.05 * smooth(t / 0.7) * (if t < 0.86 then 1 else 0), 0) * CFrame.Angles(pitch * k, 0, 0)
		local reach = hold(t, 0.1, 0.7, 0.95, 1.5) -- the tissue comes up to the nose
		p.R *= CFrame.Angles(0.95 * reach, 0, -0.25 * reach)
		if main then
			face = if t >= 0.25 and t < 0.7 then "Ooh" elseif t >= 0.7 and t < 1.05 then main else nil
		end
		squint = t >= 0.55 and t < 1.1
		fire("Achoo", 0.72, 14)
	elseif motion == "Cough" then
		local cough = pulse(t, 0.22) + pulse(t - 0.32, 0.22) + pulse(t - 0.64, 0.22)
		p.Body *= lift(u, 0, -0.03 * cough * k, 0) * CFrame.Angles(-0.13 * cough * k, 0, 0)
		local cover = hold(t, 0, 0.15, 0.95, 1.15) -- a paw over its mouth
		p.L *= CFrame.Angles(1.3 * cover, 0, 0.45 * cover)
		squint = cough > 0.3
		fire("CoughPuff", 0.05, 3)
		fire("CoughPuff", 0.37, 3)
		fire("CoughPuff", 0.69, 3)
	elseif motion == "Dizzy" then
		local stumble = pulse(t, 1.3)
		p.Body *= lift(u, 0, -0.04 * stumble * k, 0) * CFrame.Angles(0, 0, 0.16 * stumble * k)
		p.R *= CFrame.Angles(0, 0, 0.9 * stumble)
		p.L *= CFrame.Angles(0, 0, -0.9 * stumble)
		face = if stumble > 0.2 then main else nil
	elseif motion == "Sniffle" then
		local sniff = pulse(t, 0.2) + pulse(t - 0.35, 0.2)
		p.Body *= lift(u, 0, 0.035 * sniff * k, 0) * CFrame.Angles(0.06 * sniff * k, 0, 0)
		squint = sniff > 0.3
		local rub = hold(t, 0.75, 1.0, 1.55, 1.8) -- rubs the sore cheek
		local wiggle = if quiet then 0 else 0.12 * math.sin(TAU * 4 * t)
		p.L *= CFrame.Angles(1.35 * rub, 0, (0.5 + wiggle) * rub)
	elseif motion == "Droop" then
		local peek = hold(t, 0, 0.6, 1.6, 2.4) -- looks into its empty jar
		p.R *= CFrame.Angles(0.6 * peek, 0, -0.2 * peek)
		p.Body *= lift(u, 0, -0.05 * pulse(t - 1.6, 0.6) * k, 0) * CFrame.Angles(-0.12 * peek * k, 0, 0)
		fire("Motes", 1.6, 5)
	elseif motion == "Stuck" then
		local tug = if t < 0.5 then smooth(t / 0.5) elseif t < 0.62 then 1 - smooth((t - 0.5) / 0.12) else 0
		local wobble = if t > 0.62 then math.sin(TAU * 3 * (t - 0.62)) * (1 - clamp01((t - 0.62) / 0.88)) else 0
		local y = 0.09 * tug - (if t >= 0.5 and t < 0.75 then 0.03 else 0)
		p.Body *= lift(u, 0, y * k, 0) * CFrame.Angles(0, 0, 0.09 * wobble * k)
		local pull = hold(t, 0, 0.4, 0.62, 1.1) -- pulling itself up, stuck fast
		p.R *= CFrame.Angles(0, 0, 2.1 * pull)
		p.L *= CFrame.Angles(0, 0, -2.1 * pull)
		face = if t < 0.62 then main else nil
	elseif motion == "ShakeOff" then
		local amount = hold(t, 0, 0.1, 0.7, 0.9)
		local hz = if quiet then 3 else 6
		local wag = math.sin(TAU * hz * t) * amount
		p.Body *= CFrame.Angles(0, 0.3 * wag * k, 0.06 * wag * k)
		p.R *= CFrame.Angles(0, 0, 0.4 * wag)
		p.L *= CFrame.Angles(0, 0, 0.4 * wag)
		squint = amount > 0.3
		fire("Mud", 0.15, 10)
	elseif motion == "Shiver" then
		face = if t < 0.7 then main else nil
		fire("Breath", 0.05, 3)
	elseif motion == "NoseRub" then
		local cup = hold(t, 0.1, 0.4, 0.9, 1.15) -- both paws warming its nose
		p.R = CFrame.Angles(1.25 * cup, 0, -0.55 * cup)
		p.L = CFrame.Angles(1.25 * cup, 0, 0.55 * cup)
		p.Body *= CFrame.Angles(-0.07 * cup * k, 0, 0)
		local brr = hold(t, 1.1, 1.2, 1.5, 1.7)
		p.Body *= CFrame.Angles(0, 0.14 * k * brr * math.sin(TAU * (if quiet then 3 else 8) * t), 0)
		squint = cup > 0.5
		fire("Frost", 1.1, 6)
	end
	if kit and kit.Live then
		Props.setFace(kit, face)
		Props.setSquint(kit, squint and c.Acting.Squint == true)
	end
end

-- A wave for attention: the free paw (or both), `t` seconds in.
local function wave(c: Creature, p: Pose, t: number, u: number, k: number, quiet: boolean)
	local seconds = if c.WaveBoth then ALERT_WAVE_SECONDS else WAVE_SECONDS
	local up = hold(t, 0, 0.25, seconds - 0.3, seconds)
	local hz = if quiet then 1.5 else 3
	local swing = (if quiet then 0.15 else 0.3) * math.sin(TAU * hz * t)
	local raise = (2.3 + swing) * up
	if c.ArmL then
		p.L = CFrame.Angles(0, 0, -raise)
	end
	if c.WaveBoth or not c.ArmL then
		if c.ArmR then
			p.R = CFrame.Angles(0, 0, raise)
		end
	end
	if not (c.ArmL or c.ArmR) then -- no arms: it rocks from side to side instead
		p.Body *= CFrame.Angles(0, 0, 0.08 * k * math.sin(TAU * 2 * t) * up)
	else
		p.Body *= CFrame.Angles(0, 0, -0.05 * up * k)
	end
	if c.WaveBoth and not quiet then
		p.Body *= lift(u, 0, 0.08 * math.abs(math.sin(TAU * 2.5 * t)) * up, 0)
	end
end

local function attention(c: Creature): number
	if c.State ~= "Waiting" then
		return 0
	end
	if c.Patience <= CaseActing.Attention.Alert then
		return 2
	elseif c.Patience <= CaseActing.Attention.Wave then
		return 1
	end
	return 0
end

local function between(range: { number }, scale: number): number
	return rng:NextNumber(range[1], range[2]) * scale
end

-- A night creature's glow pad is under its feet; on a seat it would be a neon slab round the chair, so it fades out
-- as the creature sits down (`hidden` 0..1) and back in as it gets up. Local only: the server's part is untouched.
-- Called every frame: at rest (fully hidden or fully shown) the value is re-asserted, because the camera's Invisicam
-- writes the same property on a part in its way and later puts back the value it found, which may be a stale one of
-- ours. Hidden always wins; shown only undoes our own "hidden" (1), so Invisicam's fade of a shown pad is left be.
local function showRing(c: Creature, hidden: number)
	local ring = c.Ring
	if not ring then
		return
	end
	if math.abs(c.RingHidden - hidden) > 1e-3 then
		c.RingHidden = hidden
		ring.LocalTransparencyModifier = hidden
	elseif hidden >= 0.999 then
		if ring.LocalTransparencyModifier ~= hidden then
			ring.LocalTransparencyModifier = hidden
		end
	elseif hidden <= 1e-3 and ring.LocalTransparencyModifier >= 0.999 then
		ring.LocalTransparencyModifier = hidden
	end
end

local function act(c: Creature, now: number, quiet: boolean)
	local k = if quiet then CALM else 1
	local grown = math.clamp(c.Root.Size.X / ROOT_SIZE, 0.02, 1.5) -- small while it pops in or out
	local u = c.Unit * grown
	local p = rest(c)
	local t = now + c.Seed
	local state = c.State
	local kit = c.Props
	local sick = state == "Arriving" or state == "Waiting"
	c.Sit = CreatureSize.sitEase(c.Sit, if c.Model:GetAttribute("Seated") == true then 1 else 0, now - c.Stamp)
	c.Stamp = now
	local sit = c.Sit

	-- Breathing, always; a ghost hovers (one on a seat rests on it).
	local breathe = 0.015 * math.sin(TAU * 0.45 * t)
	if c.Ghost and state ~= "Recovering" then
		breathe += (0.12 + (if quiet then 0 else 0.08 * math.sin(TAU * 0.4 * t))) * (1 - sit)
	end
	p.Body *= lift(u, 0, breathe, 0)

	if sick then
		idle(c, p, now, u, k, quiet)
		local level = attention(c)
		local scale = if level == 2 then 0.55 elseif level == 1 then 0.75 else 1
		-- The beat (one at a time; a wave waits for it, and it waits for a wave).
		local beatAt = c.Beat
		if beatAt and now - beatAt >= c.Seconds then
			c.Beat = nil
			beatAt = nil
			c.NextBeat = now + between(c.Acting.Every, scale) * (if quiet then 1.4 else 1)
			if kit then
				Props.setFace(kit, nil)
				Props.setSquint(kit, false)
			end
		end
		if not beatAt and not c.Wave and now >= c.NextBeat then
			c.Beat = now
			beatAt = now
			table.clear(c.Fired)
		end
		if beatAt then
			beat(c, p, now - beatAt, u, k, quiet)
		end
		-- Attention: a wave now and then; the "!" stays up while patience is low.
		local waveAt = c.Wave
		if waveAt and now - waveAt >= (if c.WaveBoth then ALERT_WAVE_SECONDS else WAVE_SECONDS) then
			c.Wave = nil
			waveAt = nil
			local every = if level == 2 then CaseActing.Attention.AlertEvery else CaseActing.Attention.WaveEvery
			c.NextWave = now + between(every, 1)
		end
		if level > 0 and not waveAt and not c.Beat and now >= c.NextWave then
			c.Wave = now
			waveAt = now
			c.WaveBoth = level == 2
		end
		if waveAt then
			wave(c, p, now - waveAt, u, k, quiet)
		end
		if kit and kit.Live then
			local bounce = if quiet then 0 else math.abs(math.sin(TAU * 1.6 * t)) * 0.35
			Props.setAlert(kit, level == 2, bounce)
			Props.animate(kit, now, if c.Beat then now - c.Beat else nil, quiet)
		end
	else
		local since = now - c.Since
		if state == "Treated" then
			local relief = pulse(since, RELIEF_SECONDS)
			p.R = CFrame.Angles(0, 0, 2.2 * relief)
			p.L = CFrame.Angles(0, 0, -2.2 * relief)
			p.Body *= CFrame.Angles(0.08 * relief * k, 0, 0)
		elseif state == "Recovering" then
			p.Body *= lift(u, 0, 0.03 * math.sin(TAU * 0.22 * t), 0)
		elseif state == "Cured" then
			local joy = hold(since, 0, 0.15, JOY_SECONDS - 0.4, JOY_SECONDS)
			local swing = if quiet then 0 else 0.35 * math.sin(TAU * 4 * since)
			p.R = CFrame.Angles(0, 0, (2.5 + swing) * joy)
			p.L = CFrame.Angles(0, 0, -(2.5 + swing) * joy)
			p.Tail = CFrame.Angles(0, 0.5 * k * math.sin(TAU * 5 * since) * joy, 0)
			if not quiet then
				p.Body *= CFrame.Angles(0, 0, 0.09 * math.sin(TAU * 2.5 * since) * joy)
			end
		elseif state == "Sad" then
			p.R = CFrame.Angles(0.15, 0, -0.15)
			p.L = CFrame.Angles(0.15, 0, 0.15)
			p.Body *= CFrame.Angles(-0.14, 0, 0)
		end
	end
	if sick and c.Tail then -- a slow, hopeful little wag
		p.Tail = CFrame.Angles(0, 0.12 * k * math.sin(TAU * 0.7 * t), 0)
	end
	if sit > 0 then -- sitting: a tiny recline under everything else, the tail curled up off the chair back
		local ease = smooth(sit)
		p.Body = CFrame.Angles(CreatureSize.SIT.Recline * ease, 0, 0) * p.Body
		p.Tail = CFrame.Angles(-CreatureSize.SIT.TailCurl * ease, 0, 0) * p.Tail
	end

	showRing(c, smooth(sit))

	c.Pose.Transform = p.Body
	if c.ArmR then
		c.ArmR.Transform = p.R
	end
	if c.ArmL then
		c.ArmL.Transform = p.L
	end
	if c.Tail then
		c.Tail.Transform = p.Tail
	end
end

-- Far away: everything back at rest, once.
local function still(c: Creature)
	if c.Still then
		return
	end
	c.Still = true
	c.Sit = if c.Model:GetAttribute("Seated") == true then 1 else 0
	showRing(c, c.Sit)
	c.Pose.Transform = IDENTITY
	for _, motor in { c.ArmR, c.ArmL, c.Tail } do
		if motor then
			motor.Transform = IDENTITY
		end
	end
	local kit = c.Props
	if kit and kit.Live then
		Props.setFace(kit, nil)
		Props.setSquint(kit, false)
		Props.setAlert(kit, false, 0)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Props on and off
------------------------------------------------------------------------------------------------------------------

local function dropProps(c: Creature, poof: boolean)
	local kit = c.Props
	if kit and kit.Live then
		Props.remove(kit, poof)
	end
end

local function updateProps(c: Creature, quiet: boolean)
	local sick = c.State == "Arriving" or c.State == "Waiting"
	local grown = c.Root.Size.X / ROOT_SIZE
	local kit = c.Props
	if sick and not kit and grown >= 0.95 then
		local ok, built = pcall(Props.build, c.Model, c.Acting)
		if ok and built then
			c.Props = built
			Props.ambient(built, true, quiet)
		elseif not ok then
			warn("[CreatureActing] props: " .. tostring(built))
			c.Props = nil
		end
	elseif kit and kit.Live and grown < 0.9 then
		Props.remove(kit, false) -- shrinking away: the props go first
	end
end

local function onState(c: Creature)
	local new = phaseOf(c.Model:GetAttribute("State"), c.State)
	if new == c.State then
		return
	end
	c.State = new
	c.Since = os.clock()
	c.Beat = nil
	c.Wave = nil
	local live = c.Props
	if live and live.Live then -- a beat cut short (the line moved up): no face left stuck on
		Props.setFace(live, nil)
		Props.setSquint(live, false)
	end
	if new == "Treated" or new == "Recovering" or new == "Cured" then
		dropProps(c, new == "Treated")
	elseif new == "Sad" or new == "Calm" then
		dropProps(c, false)
	end
	if new == "Cured" then
		local kit = c.Props
		if kit and c.Near then
			Props.burst(kit, "Joy", if calm() then 10 else 28)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Tracking creatures as they stream in and out
------------------------------------------------------------------------------------------------------------------

local function step()
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local quiet = calm()
	for model, c in creatures do
		if not model.Parent then
			continue
		end
		if now >= c.NextCheck then
			c.NextCheck = now + CHECK_SECONDS
			c.Near = (c.Root.Position - eye).Magnitude <= NEAR_STUDS
			updateProps(c, quiet)
		end
		if not c.Near then
			still(c)
			continue
		end
		c.Still = false
		local ok, err = pcall(act, c, now, quiet)
		if not ok then
			warn("[CreatureActing] " .. tostring(err))
			c.Near = false
			c.NextCheck = now + 5
		end
	end
end

local function untrack(model: Instance)
	local c = creatures[model :: Model]
	if not c then
		return
	end
	creatures[model :: Model] = nil
	count -= 1
	for _, connection in c.Connections do
		connection:Disconnect()
	end
	if count <= 0 and stepConnection then
		stepConnection:Disconnect() -- nobody to act: no loop running at all
		stepConnection = nil
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or creatures[instance] or not instance.Parent then
		return
	end
	local model = instance
	local root = model.PrimaryPart
	local core = model:FindFirstChild("Core")
	local pose = root and root:FindFirstChild("PoseJoint")
	if not (root and core and pose and pose:IsA("Motor6D")) then
		return -- not (yet) a creature built by CreatureBuilder
	end
	local function motor(name: string): Motor6D?
		local found = core:FindFirstChild(name)
		return if found and found:IsA("Motor6D") then found else nil
	end
	local acting: Acting = actingOf(model)
	local unit = model:GetAttribute("BuildScale")
	local hasFeet = model:FindFirstChild("Foot") ~= nil
	local now = os.clock()
	local c: Creature = {
		Model = model,
		Root = root,
		Pose = pose,
		ArmR = motor("ArmRJoint"),
		ArmL = motor("ArmLJoint"),
		Tail = motor("TailJoint"),
		Ring = (function(): BasePart?
			local ring = model:FindFirstChild("GlowRing")
			return if ring and ring:IsA("BasePart") then ring else nil
		end)(),
		RingHidden = 0,
		Unit = if type(unit) == "number" and unit > 0 then unit else 1.6,
		Acting = acting,
		Seconds = BEAT_SECONDS[acting.Motion] or 1,
		State = "",
		Patience = 1,
		Props = nil,
		Seed = rng:NextNumber(0, 10),
		Ghost = model:GetAttribute("Night") == true and not hasFeet,
		Near = false,
		NextCheck = 0,
		Still = false,
		NextBeat = now + rng:NextNumber(0.6, 2.5),
		Beat = nil,
		Fired = {},
		NextWave = now + rng:NextNumber(1, 3),
		Wave = nil,
		WaveBoth = false,
		Since = now,
		Sit = if model:GetAttribute("Seated") == true then 1 else 0, -- one that streams in seated is sitting
		Stamp = now,
		Connections = {},
	}
	onState(c)
	local fraction = model:GetAttribute("PatienceFraction")
	c.Patience = if type(fraction) == "number" then fraction else 1
	table.insert(
		c.Connections,
		model:GetAttributeChangedSignal("State"):Connect(function()
			onState(c)
		end)
	)
	table.insert(
		c.Connections,
		model:GetAttributeChangedSignal("PatienceFraction"):Connect(function()
			local value = model:GetAttribute("PatienceFraction")
			c.Patience = if type(value) == "number" then value else 1
		end)
	)
	-- The symptom (or, after the exam, the case) can arrive after the model: act it out once it's known.
	local function recast()
		local nextActing = actingOf(model)
		if nextActing == c.Acting then
			return
		end
		c.Acting = nextActing
		c.Seconds = BEAT_SECONDS[nextActing.Motion] or 1
		c.Beat = nil
		local kit = c.Props
		if kit and kit.Live then
			Props.remove(kit, false) -- the new props come with the next check (updateProps)
		end
		c.Props = nil
	end
	for _, name in { "Case", "Acting", "Symptom" } do
		table.insert(c.Connections, model:GetAttributeChangedSignal(name):Connect(recast))
	end
	table.insert(
		c.Connections,
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				untrack(model)
			end
		end)
	)
	creatures[model] = c
	count += 1
	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

function CreatureActing.init(_ctx: Types.Ctx)
	-- Every prop and motion named in the data has a player here (a typo in the data only warns).
	for _, name in CaseActing.Vocabulary.Props do
		if not Props.has(name) then
			warn("[CreatureActing] no prop builder for " .. name)
		end
	end
	for _, name in CaseActing.Vocabulary.Motions do
		if not BEAT_SECONDS[name] then
			warn("[CreatureActing] no motion for " .. name)
		end
	end
	for _, instance in CollectionService:GetTagged(TAG) do
		task.defer(track, instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		-- Streaming can deliver the model a moment before its parts and attributes are in place.
		task.defer(track, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
end

return CreatureActing
