--!strict
-- Cases: what is wrong with a patient (Real Clinic build plan, contract C3; design §6 and §15 #2). They replace the
-- ailments. Lune-safe (no Roblox types). Iterate `Cases.ORDER` (also `Cases.Order`); `for id, case in Cases` yields
-- only cases.
-- Gentle and realistic only (Rated Minimal): nothing sharp, bloody or scary, and never an operation.
--
--   Name    the reveal after the exam ("It's a cough!") and the Guide
--   Icon    the case's own picture
--   Bubble  the symptom a waiting patient shows BEFORE the exam (the case itself stays hidden until then)
--   Tool    the exam tool that finds it (Data/Tools)
--   Plan    the treatment, 1-3 ItemIds in order (Data/Items). The hospital level cuts it (Data/Levels.RecipeCap,
--           Logic/Visit.plan), so a Lv 1 player always sees one step
--   Stay    after the plan, the patient rests upstairs: "Wards" (the Injury Ward, from Lv 2) or "Rest" (the Rest
--           Ward, from Lv 3). Below that level it just goes home (Logic/Visit.stayWard)
--   Level   the hospital level the case comes from
--   Room    a RoomId (Data/Rooms) the clinic must own as well
-- A clinic only ever gets a case it can treat: its level, its rooms, and every plan item's station open
-- (Logic/Visit.canTreat).
--
-- Cases.POOLS: a patient's case is rolled each visit from its WING's pool (Data/Wings ids), cut to what that clinic
-- can treat (Logic/Visit.rollCase). An id listed more than once is that much likelier: a Bath or Winter patient
-- usually brings its own room's case. Night patients come to every clinic, so their pool is Lv 1 cases only.
-- Regulars have one fixed case each (Data/Regulars).

export type CaseId = string
export type Case = {
	Name: string,
	Icon: string,
	Bubble: string,
	Tool: string, -- ToolId
	Plan: { string }, -- ItemIds
	Stay: ("Wards" | "Rest")?,
	Level: number,
	Room: string?,
}

local ENTRIES: { [CaseId]: Case } = {
	Cough = {
		Name = "Cough",
		Icon = "😷",
		Bubble = "😷 cough cough",
		Tool = "Stethoscope",
		Plan = { "CoughSyrup" },
		Level = 1,
	},
	Fever = {
		Name = "Fever",
		Icon = "🤒",
		Bubble = "🤒 so hot",
		Tool = "Thermometer",
		Plan = { "FeverMeds" },
		Stay = "Rest",
		Level = 1,
	},
	CutKnee = {
		Name = "Cut knee",
		Icon = "🩹",
		Bubble = "🩹 ouchie",
		Tool = "Magnifier",
		Plan = { "Plaster" },
		Level = 1,
	},
	BumpedHead = {
		Name = "Bumped head",
		Icon = "💫",
		Bubble = "💫 bonk",
		Tool = "Magnifier",
		Plan = { "Ice" },
		Level = 1,
	},
	Earache = {
		Name = "Earache",
		Icon = "👂",
		Bubble = "👂 ow ow",
		Tool = "Light",
		Plan = { "EarDrops" },
		Level = 1,
	},
	Sprain = {
		Name = "Sprained ankle",
		Icon = "🦶",
		Bubble = "🦶 can't walk",
		Tool = "Magnifier",
		Plan = { "Ice", "Bandage" },
		Stay = "Wards", -- design §15 #3: the Injury Ward is for sprains and broken bones, so it is used from Lv 2
		Level = 2,
	},
	SoreThroat = {
		Name = "Sore throat",
		Icon = "🗣️",
		Bubble = "🗣️ scratchy",
		Tool = "Light",
		Plan = { "Lozenges", "CoughSyrup" },
		Level = 2,
	},
	Rash = {
		Name = "Itchy rash",
		Icon = "😖",
		Bubble = "😖 itchy",
		Tool = "Magnifier",
		Plan = { "Cream", "Ice" },
		Level = 2,
	},
	BrokenArm = {
		Name = "Broken arm",
		Icon = "💢",
		Bubble = "💢 my arm",
		Tool = "XRay",
		Plan = { "Cast", "PainRelief" },
		Stay = "Wards",
		Level = 3,
	},
	SoreMuscles = {
		Name = "Sore muscles",
		Icon = "😩",
		Bubble = "😩 achy",
		Tool = "Magnifier",
		Plan = { "Bubbles", "PainRelief" },
		Level = 1,
		Room = "BathRoom",
	},
	Chills = {
		Name = "Chills",
		Icon = "🥶",
		Bubble = "🥶 brrr",
		Tool = "Thermometer",
		Plan = { "Cocoa", "FeverMeds" },
		Stay = "Rest",
		Level = 1,
		Room = "WinterWing",
	},
	BrokenLeg = { -- the helicopter's VIP
		Name = "Broken leg",
		Icon = "💢",
		Bubble = "💢 my leg",
		Tool = "XRay",
		Plan = { "Cast", "PainRelief", "Bandage" },
		Stay = "Wards",
		Level = 5,
	},
}

local ORDER = {
	"Cough",
	"Fever",
	"CutKnee",
	"BumpedHead",
	"Earache",
	"Sprain",
	"SoreThroat",
	"Rash",
	"BrokenArm",
	"SoreMuscles",
	"Chills",
	"BrokenLeg",
}

local STARTER = { "Cough", "Fever", "CutKnee", "BumpedHead", "Earache", "Sprain", "SoreThroat", "Rash", "BrokenArm" }

-- `first` three times (so the wing's own case is the likeliest), then the Starter pool.
local function withStarter(first: CaseId): { CaseId }
	local pool = { first, first, first }
	for _, id in STARTER do
		table.insert(pool, id)
	end
	return pool
end

local POOLS: { [string]: { CaseId } } = {
	Starter = STARTER,
	Night = { "Cough", "Fever", "Earache" },
	Bath = withStarter("SoreMuscles"),
	Winter = withStarter("Chills"),
	Sunny = { "Rash", "Sprain", "CutKnee" },
	Sky = { "BrokenLeg" },
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = {
	ORDER: { CaseId },
	Order: { CaseId },
	POOLS: { [string]: { CaseId } },
	[CaseId]: Case,
}
local order = freeze(ORDER)
return freeze(setmetatable(ENTRIES, { __index = { ORDER = order, Order = order, POOLS = freeze(POOLS) } })) :: Module
