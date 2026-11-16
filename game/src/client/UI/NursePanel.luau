--!strict
-- NursePanel (depth-update design §2, build plan §B9; memory-20261116-012/-013; Progression v2 build plan §B3/§B9,
-- §C T5, memory-20261116-017/-019). OWNER: T5.
-- The 👩‍⚕️ Nurses panel: the Nurse Journal (a bestiary of every nurse, by rarity) and your Team (the roster).
--   init(ctx)   opens on ctx.fire("Open", "Nurses", "Team" | "Branch" | rarity?) (the Hud's 👩‍⚕️ button, anyone);
--               listens for "NurseNews" and "MarketNews" (🏷️ on your listed nurses); fires "NursesNew" (count) for
--               the button's dot, "Open" ("NurseOdds") for UI/BeltView's odds popup, "Open" ("Agency") / "Open"
--               ("Market") from the strip, "Sell" (nurseId) / "List" (nurseId) from a Team card (UI/AgencyPanel's
--               sell confirm, UI/MarketPanel's list flow), and "Sound" (Sparkle, Click; Hire and Job cues come with
--               NurseNews in Feel/Sounds). Asks SetJob(nurseId, job), ClaimBranchNurse() and, once, GetMarket().
--   NursePanel.Pure   the pure helpers below (tests/NurseUI.spec loads the block on its own)
--
-- Inside (a Hud.modal Panel, cyan like its HUD button):
--   header    "👩‍⚕️ Journal" / "👩‍⚕️ Team" and a completion pill "📔 n%" (hired out of all, Logic/Nurse.journal;
--             rebirth-only nurses are left out of it)
--   strip     👩‍⚕️ Team n/cap · 📔 Journal (the two views) · 🏢 Agency · 🏷️ Market
--   Journal   (stays first) tabs down the left, one per rarity (Data/Rarities.Order) with hired/total (✅ when the
--             group is done) and a dot for news inside, plus a 🏢 tab for rebirth-only nurses (FounderFennec):
--               a rarity page: its header (icon, "Night Rush only" / "Golden Hour only", a progress bar, the group
--               reward 💰 + decor with ✅ and rays once JournalSets has it, a 🎲 chip with the odds right now) and a
--               card per nurse: unseen (a silhouette, "???", where to find it) · seen (greyed, its name, job, belt
--               price) · hired (full colour with a cap in the rarity's colour, level and stat, 👩‍⚕️ Team; ✅ while it
--               works, 💤 while it rests)
--               the 🏢 page: a card per rebirth-only nurse: "🏢 R5" until then, 🎁 Claim while it waits for a roster
--               place (Rebirth.Pending), then hired
--   Team      the roster "👩‍⚕️ n/cap" (Logic/Nurse.rosterCap: 3, +1 a rebirth, at most 8), "💤 n resting" for an
--             over-cap save, the team chips ("🛎️ ×2 +10% 💰", Logic/Jobs.teams/Data/Departments) or a hint, the 🎁 gift
--             row, then one big card per nurse (working first, then resting): its face and level, an XP bar (⭐ MAX at
--             the level cap), its specialty, its ability with a Kit.ring that fills as it recharges (from the plot
--             nurse's AbilityReadyAt / AbilityCooldown; never seconds), the job button (opens the job picker), and
--             💰 Sell → "Sell" · 🏷️ List → "List" (🏷️ Listed opens the Market); a rebirth-only nurse "🏢 Stays with
--             you". Cards with news wear NEW! / ⬆️.
--   job picker  a Popup over the panel: every job (Data/Jobs) with its icon, name and words, ✅ on the one it works,
--             "🏥 Lv 2" for one not open yet, 💤 for a resting nurse while the roster is full, ⭐ where its specialty
--             gives +40%. Tapping an open job asks SetJob.
-- NEW! moments: a nurse seen for the first time, a copy that levels one up and a level from XP pop a little stamp card
-- above the 👩‍⚕️ button that flies into it (fades with reduced motion; none during the first-session tutorial or while
-- the panel is open, where the card pops instead). A first hire's big moment is UI/Celebrate's (the server's
-- "Celebrate" NewNurse). NursesNew counts Seen, Hired and Level news until the panel closes.
-- Reads only the Snapshot (NurseIndex, Nurses, JournalSets, Level, Cash, Rebirth), MarketNews, the plot nurses'
-- ability attributes, and Workspace's GoldenHour / NightRush (for the 🎲 chips). The server decides everything; this
-- panel only asks. The ring loop runs only while the Team view is open (4 updates a second) and sleeps otherwise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Logic = Shared:WaitForChild("Logic")
local BeltLogic = require(Logic:WaitForChild("Belt"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local JobsLogic = require(Logic:WaitForChild("Jobs"))
local AbilitiesLogic = require(Logic:WaitForChild("Abilities"))
local TutorialLogic = require(Logic:WaitForChild("Tutorial"))
local BeltView = require(script.Parent.BeltView)
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BeltPure = BeltView.Pure

local NursePanel = {}

local ACCENT = Theme.Colors.Cyan
local TAB_WIDTH = Theme.Size.IconButton
local SLOT = Theme.Size.ButtonHeight
local STRIP_HEIGHT = SLOT + 8
local MODE_WIDTH = 158
local LINK_WIDTH = 136
local PILL_WIDTH = 118
local MIN_CARD = 112
local CARD_GAP = 10
-- Under each card's face: 4 gap + name 22 + info 20 + 4 gap + the button + 6, plus the face's 6 on top.
local CARD_FIXED = 6 + 4 + 22 + 20 + 4 + SLOT + 6
local HEADER_HEIGHT = 8 + 44 + 6 + 14 + 8 + SLOT + 8
local BRANCH_HEADER_HEIGHT = 8 + 44 + 6 + 14 + 8
local ODDS_WIDTH = 100
local STAMP_SIZE = Vector2.new(132, 156)
local STAMP_SECONDS = 1.7
local STAMP_QUEUE_MAX = 4
local UNSEEN_FILL = Kit.lighten(Theme.Colors.Disabled, 0.55)
local UNSEEN_FACE = Kit.lighten(Theme.Colors.Disabled, 0.2)
local SEEN_FACE = Kit.lighten(Theme.Colors.Disabled, 0.45)
local RESTING_FILL = Kit.lighten(Theme.Colors.Disabled, 0.62)
-- The Team card: a face on the left, name / XP / chips beside it, the ability ring top right, buttons along the foot.
local FACE = 72
local LEFT = 8 + FACE + 10
local RING = 56
local ACTION_WIDTH = 96
local TEAM_CARD_HEIGHT = 8 + FACE + 8 + SLOT + 8
local TEAM_TWO_UP = 680 -- two cards a row from this width
local RING_STEP = 0.25
local JOB_ROW_HEIGHT = 68

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types, only BeltPure (UI/BeltView's pure block) and the shared Logic modules
-- NurseLogic, JobsLogic and AbilitiesLogic. tests/NurseUI.spec loads the block between the PURE markers on its own,
-- so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.ROLE_NAMES = { Maker = "Maker", Healer = "Healer", Cheerer = "Cheerer" } :: { [string]: string }

-- Every fixed label on the panel (NurseUI.spec checks each is ≤ 6 words).
Pure.TEXT = {
	TitleJournal = "👩‍⚕️ Journal",
	TitleTeam = "👩‍⚕️ Team",
	Journal = "📔 Journal",
	Agency = "🏢 Agency",
	Market = "🏷️ Market",
	Sell = "💰 Sell",
	List = "🏷️ List",
	Listed = "🏷️ Listed",
	UnlistFirst = "🏷️ Unlist it first",
	Stays = "🏢 Stays with you",
	Resting = "💤 Resting",
	PickJob = "💼 Pick a job",
	TeamHint = "🤝 Pair specialties for team bonuses",
	Empty = "🎠 Hire nurses on the belt!",
	GiftHead = "🎁 A nurse waits!",
	Claim = "🎁 Claim",
	RosterFull = "Roster full: sell or list one",
	SeeTeam = "👩‍⚕️ Team",
	BranchName = "Branch nurses",
	BranchNote = "🏢 From new branches",
	BranchTab = "🏢",
	Max = "⭐ MAX",
	New = "NEW!",
	LevelUp = "⬆️",
	Oops = "Oops! Try again.",
	Busy = "⏳",
}

export type RosterView = {
	Owned: number,
	Cap: number,
	Working: { string },
	Resting: { string },
	Text: string,
	RestText: string,
	Full: boolean,
}
export type TeamChip = { Dept: string, Count: number, Text: string }
export type Xp = { Level: number, XP: number, Need: number, Fraction: number, Max: boolean }
export type JobOption = {
	Id: string,
	Icon: string,
	Name: string,
	Text: string,
	State: string, -- "Current" | "Open" | "Closed" | "Full"
	Caption: string,
	Boost: boolean,
}
export type Actions = { Sell: boolean, List: boolean, Listed: boolean, Stays: boolean }
export type Gift = { NurseId: string, Room: boolean }

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function whole(value: any): number
	return math.max(0, math.floor(num(value, 0)))
end

local function row(map: any, id: any): any
	if type(map) ~= "table" or type(id) ~= "string" then
		return nil
	end
	local value = rawget(map, id)
	return if type(value) == "table" then value else nil
end

local function ordered(map: any): { string }
	local ids: { string } = {}
	if type(map) == "table" and type(map.Order) == "table" then
		for _, id in map.Order do
			if type(id) == "string" and row(map, id) then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-- How many words a label has: tokens with a letter in them (emoji, numbers and "·" aren't words).
function Pure.words(text: any): number
	if type(text) ~= "string" then
		return 0
	end
	local n = 0
	for token in string.gmatch(text, "%S+") do
		if string.find(token, "%a") then
			n += 1
		end
	end
	return n
end

-- A nurse's Journal state: "Hired" · "Seen" · "Unseen" (no entry, or junk).
function Pure.mark(index: any, nurseId: string): string
	local value = if type(index) == "table" then index[nurseId] else nil
	return if value == "Hired" then "Hired" elseif value == "Seen" then "Seen" else "Unseen"
end

-- News since the panel was last opened: fresh[nurseId] = "Level" | "Seen" | "Hired". A stronger kind replaces a
-- weaker one (Hired over Seen over Level), never the other way round; other NurseNews kinds aren't news. Returns
-- true when `fresh` changed.
local NEWS_RANK: { [string]: number } = { Level = 1, Seen = 2, Hired = 3 }
function Pure.noteNews(fresh: { [string]: string }, info: any): boolean
	if type(info) ~= "table" or type(info.NurseId) ~= "string" then
		return false
	end
	local rank = NEWS_RANK[info.Kind]
	if not rank then
		return false
	end
	local current = fresh[info.NurseId]
	if current and (NEWS_RANK[current] or 0) >= rank then
		return false
	end
	fresh[info.NurseId] = info.Kind
	return true
end

function Pure.count(fresh: { [string]: string }): number
	local n = 0
	for _ in fresh do
		n += 1
	end
	return n
end

-- "Lv 2" · "Lv 10 MAX" at the level cap (an entry without a level counts as Lv 1).
function Pure.levelText(entry: any, cap: number): string
	local level = if type(entry) == "table" and type(entry.Level) == "number" then math.floor(entry.Level) else 1
	if level >= cap then
		return "Lv " .. level .. " MAX"
	end
	return "Lv " .. level
end

-- A group's reward line: "💰300 + 🩹" (in-game cash, then the decor's icon).
function Pure.rewardText(rarity: any, decorIcon: string?): string
	local journal = if type(rarity) == "table" and type(rarity.Journal) == "table" then rarity.Journal else {}
	local cash = if type(journal.Cash) == "number" then journal.Cash else 0
	local text = "💰" .. BeltPure.short(cash)
	if type(decorIcon) == "string" and decorIcon ~= "" then
		text ..= " + " .. decorIcon
	end
	return text
end

-- Under a card with no button: where to find an unseen nurse (an event rarity names its event), or your belt price
-- for a seen one.
function Pure.hint(mark: string, rarity: any, price: number): string
	if mark == "Unseen" then
		local event = if type(rarity) == "table" then rarity.Event else nil
		if event == "NightRush" then
			return "🌙 Night Rush"
		elseif event == "GoldenHour" then
			return "👑 Golden Hour"
		end
		return "👀 On the belt"
	end
	return "💰" .. BeltPure.short(price)
end

-- A page's note under its name: Mythic and Secret only come during their event.
function Pure.eventNote(rarity: any): string
	local event = if type(rarity) == "table" then rarity.Event else nil
	if event == "NightRush" then
		return "🌙 Night Rush only"
	elseif event == "GoldenHour" then
		return "👑 Golden Hour only"
	end
	return ""
end

-- Which view opens: the one asked for ("Team", "Branch" or a rarity), else the lowest rarity page with journal
-- news, else the 🏢 page with news, else the Team page with level news, else where you were, else the first page.
function Pure.openView(tab: any, fresh: { [string]: string }, roster: any, order: { string }, current: string?): string
	if tab == "Team" or tab == "Branch" then
		return tab
	end
	if type(tab) == "string" and table.find(order, tab) then
		return tab
	end
	for _, rarity in order do
		for nurseId, kind in fresh do
			local nurse = row(roster, nurseId)
			if kind ~= "Level" and nurse and nurse.Source == nil and nurse.Rarity == rarity then
				return rarity
			end
		end
	end
	for nurseId, kind in fresh do
		local nurse = row(roster, nurseId)
		if kind ~= "Level" and nurse and nurse.Source ~= nil then
			return "Branch"
		end
	end
	for nurseId, kind in fresh do
		if kind == "Level" and row(roster, nurseId) then
			return "Team"
		end
	end
	if current == "Team" or current == "Branch" or (current ~= nil and table.find(order, current) ~= nil) then
		return current :: string
	end
	return order[1]
end

-- The roster: who works (Logic/Nurse.working: the cap's first, by NurseId), who rests (the rest, by NurseId), and
-- "👩‍⚕️ owned/cap" (resting nurses count: Logic/Nurse.canAdd says the same).
function Pure.roster(nurses: any, rebirths: number, cfg: any, roster: any): RosterView
	local function isKnown(id: string): boolean
		return row(roster, id) ~= nil
	end
	local cap = NurseLogic.rosterCap(rebirths, cfg)
	local working = NurseLogic.working(nurses, cap, isKnown)
	local resting: { string } = {}
	if type(nurses) == "table" then
		for nurseId, entry in nurses do
			if type(nurseId) == "string" and type(entry) == "table" and isKnown(nurseId) then
				if not table.find(working, nurseId) then
					table.insert(resting, nurseId)
				end
			end
		end
	end
	table.sort(resting)
	local owned = NurseLogic.owned(nurses, isKnown)
	return {
		Owned = owned,
		Cap = cap,
		Working = working,
		Resting = resting,
		Text = "👩‍⚕️ " .. owned .. "/" .. cap,
		RestText = if #resting > 0 then "💤 " .. #resting .. " resting" else "",
		Full = owned >= cap,
	}
end

-- A team bonus in a few words: "+10% 💰" · "🚑 wait +25%" · "rest 25% faster" · "☕💊 20% faster".
function Pure.effectText(effect: any, stationIcons: { [string]: string }?): string
	if type(effect) ~= "table" then
		return ""
	end
	local percent = math.floor(num(effect.Value, 0) * 100 + 0.5)
	if effect.Kind == "Cash" then
		return "+" .. percent .. "% 💰"
	elseif effect.Kind == "Urgent" then
		return "🚑 wait +" .. percent .. "%"
	elseif effect.Kind == "Recover" then
		return "rest " .. percent .. "% faster"
	elseif effect.Kind == "Make" then
		local icons = ""
		for _, stationId in (if type(effect.Stations) == "table" then effect.Stations else {}) do
			icons ..= if stationIcons and stationIcons[stationId] then stationIcons[stationId] else ""
		end
		return (if icons ~= "" then icons .. " " else "") .. percent .. "% faster"
	end
	return ""
end

-- The team chips: each department with 2 or more WORKING specialists (Logic/Jobs.teams; "Any" counts for every
-- one), with the bonus it gives now (2 = Team2, 3+ = Team3).
function Pure.teamChips(
	working: { string },
	roster: any,
	departments: any,
	stationIcons: { [string]: string }?
): { TeamChip }
	local specialties: { string } = {}
	for _, nurseId in working do
		local nurse = row(roster, nurseId)
		if nurse and type(nurse.Specialty) == "string" then
			table.insert(specialties, nurse.Specialty)
		end
	end
	local counts = JobsLogic.teams(specialties, departments)
	local out: { TeamChip } = {}
	for _, deptId in ordered(departments) do
		local n = whole(counts[deptId])
		local dept = row(departments, deptId)
		local effect = if n >= 3 then dept.Team3 elseif n == 2 then dept.Team2 else nil
		if type(effect) == "table" then
			table.insert(out, {
				Dept = deptId,
				Count = n,
				Text = dept.Icon .. " ×" .. n .. "  " .. Pure.effectText(effect, stationIcons),
			})
		end
	end
	return out
end

-- "🛎️ Reception" · "🌟 Any" · "" (unknown).
function Pure.specialtyText(specialty: any, departments: any): string
	if specialty == "Any" then
		return "🌟 Any"
	end
	local dept = row(departments, specialty)
	return if dept then dept.Icon .. " " .. dept.Name else ""
end

-- "⭐ +40% at its specialty" (Config.Nurses.SpecialtyBoost).
function Pure.boostText(cfg: any): string
	local s = if type(cfg) == "table" and type(cfg.Nurses) == "table" then cfg.Nurses else {}
	return "⭐ +" .. math.floor(num(s.SpecialtyBoost, 0) * 100 + 0.5) .. "% at its specialty"
end

-- The XP bar: how full it is toward the next level; full and Max at the level cap.
function Pure.xp(entry: any, cap: number): Xp
	local e = if type(entry) == "table" then entry else {}
	local level = math.max(1, whole(e.Level))
	if level >= math.max(1, whole(cap)) then
		return { Level = level, XP = 0, Need = 0, Fraction = 1, Max = true }
	end
	local need = NurseLogic.xpToNext(level)
	local xp = math.clamp(whole(e.XP), 0, need)
	return { Level = level, XP = xp, Need = need, Fraction = xp / need, Max = false }
end

-- On the bar: "12/70", or "⭐ MAX".
function Pure.xpText(xp: Xp): string
	return if xp.Max then Pure.TEXT.Max else xp.XP .. "/" .. xp.Need
end

-- "🎵 Calm Song" · "🎵 Calm Song ★★" once Lv 5 / Lv 10 made it stronger (Logic/Abilities.tier).
function Pure.abilityText(abilityId: any, level: number, abilities: any, cfg: any): string
	local def = row(abilities, abilityId)
	if not def then
		return ""
	end
	local tier = AbilitiesLogic.tier(level, cfg)
	return def.Icon .. " " .. def.Name .. (if tier > 0 then " " .. string.rep("★", tier) else "")
end

-- The ability ring: 1 = ready (no times known counts as ready: abilities fire by themselves), else how much of
-- the cooldown has passed. Never seconds.
function Pure.ringFraction(readyAt: any, cooldown: any, now: any): number
	if type(readyAt) ~= "number" or readyAt ~= readyAt then
		return 1
	end
	local left = readyAt - num(now, 0)
	if left <= 0 then
		return 1
	end
	local length = num(cooldown, 0)
	if length <= 0 then
		return 0
	end
	return math.clamp(1 - left / length, 0, 1)
end

-- The job gives this nurse its +40% (its specialty is the job's department; a Maker's is its station's, so any
-- department with a station counts; "Any" always does).
function Pure.boosted(jobId: string, specialty: any, jobs: any, stations: any): boolean
	if specialty == "Any" then
		return true
	end
	local job = row(jobs, jobId)
	if not job or type(specialty) ~= "string" then
		return false
	end
	if job.Dept == "Station" then
		if type(stations) == "table" then
			for _, dept in stations do
				if dept == specialty then
					return true
				end
			end
		end
		return false
	end
	return job.Dept == specialty
end

-- The job picker's rows, in Data/Jobs order: "Current" (✅ the job it works: Logic/Jobs.effective) · "Closed"
-- ("🏥 Lv 2": not open at this hospital level) · "Full" (💤: a resting nurse while the roster is full) · "Open".
function Pure.jobOptions(
	entry: any,
	nurse: any,
	level: number,
	jobs: any,
	resting: boolean,
	working: number,
	cap: number,
	stations: any
): { JobOption }
	local role = if type(nurse) == "table" and type(nurse.Role) == "string" then nurse.Role else "Maker"
	local saved = if type(entry) == "table" then entry.Job else ""
	local effective = JobsLogic.effective(saved, role, level, jobs)
	local out: { JobOption } = {}
	for _, jobId in ordered(jobs) do
		local job = row(jobs, jobId)
		local kind, caption = "Open", ""
		if not resting and effective == jobId then
			kind, caption = "Current", "✅"
		elseif not JobsLogic.open(jobId, level, jobs) then
			kind, caption = "Closed", "🏥 Lv " .. math.max(1, whole(job.Opens))
		elseif resting and working >= cap then
			kind, caption = "Full", "💤"
		end
		table.insert(out, {
			Id = jobId,
			Icon = job.Icon,
			Name = job.Name,
			Text = job.Text,
			State = kind,
			Caption = caption,
			Boost = Pure.boosted(jobId, if type(nurse) == "table" then nurse.Specialty else nil, jobs, stations),
		})
	end
	return out
end

-- What tapping a row that can't be asked for says (the server's own words); nil = ask (Open) or nothing (Current).
function Pure.jobMessage(option: JobOption): string?
	if option.State == "Closed" then
		return option.Caption .. " first!"
	elseif option.State == "Full" then
		return Pure.TEXT.RosterFull
	end
	return nil
end

-- The job button on a Team card: the job it works now, and the job it was given when that isn't open yet
-- ("🧪 Maker (🛗 at 🏥 Lv 2)"); "💤 Resting" for a resting nurse.
function Pure.jobButton(entry: any, nurse: any, level: number, jobs: any, resting: boolean): string
	if resting then
		return Pure.TEXT.Resting
	end
	local role = if type(nurse) == "table" and type(nurse.Role) == "string" then nurse.Role else "Maker"
	local saved = if type(entry) == "table" then entry.Job else ""
	local effective = JobsLogic.effective(saved, role, level, jobs)
	local job = row(jobs, effective)
	local text = if job then job.Icon .. " " .. job.Name else effective
	if type(saved) == "string" and saved ~= "" and saved ~= effective then
		local waiting = row(jobs, saved)
		if waiting then
			text ..= " (" .. waiting.Icon .. " at 🏥 Lv " .. math.max(1, whole(waiting.Opens)) .. ")"
		end
	end
	return text
end

-- A Team card's buttons: Sell and List (🏷️ Listed while it's on the Market); a rebirth-only nurse has neither
-- ("🏢 Stays with you").
function Pure.actions(nurseId: string, roster: any, listed: { [string]: boolean }?): Actions
	if NurseLogic.isRebirthOnly(roster, nurseId) then
		return { Sell = false, List = false, Listed = false, Stays = true }
	end
	return { Sell = true, List = true, Listed = listed ~= nil and listed[nurseId] == true, Stays = false }
end

-- Your nurses on the Market (MarketView.Listings with you as the Seller).
function Pure.listedSet(view: any, userId: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local listings = if type(view) == "table" then view.Listings else nil
	if type(listings) == "table" then
		for _, listing in ipairs(listings) do
			if type(listing) == "table" and listing.Seller == userId and type(listing.NurseId) == "string" then
				out[listing.NurseId] = true
			end
		end
	end
	return out
end

-- The first rebirth-only nurse waiting for a roster place (Rebirth.Pending), and whether there's room now.
function Pure.gift(state: any, roster: any, cfg: any): Gift?
	local rebirth = if type(state) == "table" and type(state.Rebirth) == "table" then state.Rebirth else {}
	local pending = if type(rebirth.Pending) == "table" then rebirth.Pending else {}
	for _, nurseId in ipairs(pending) do
		if row(roster, nurseId) then
			local view = Pure.roster(state.Nurses, whole(rebirth.Count), cfg, roster)
			return { NurseId = nurseId, Room = view.Owned < view.Cap }
		end
	end
	return nil
end

-- A rebirth-only nurse's card on the 🏢 page: "Owned" · "Pending" (🎁 Claim) · "Locked" ("🏢 R5").
function Pure.branchCard(nurseId: string, state: any): string
	local nurses = if type(state) == "table" then state.Nurses else nil
	if type(nurses) == "table" and type(nurses[nurseId]) == "table" then
		return "Owned"
	end
	local rebirth = if type(state) == "table" and type(state.Rebirth) == "table" then state.Rebirth else {}
	if type(rebirth.Pending) == "table" and table.find(rebirth.Pending, nurseId) then
		return "Pending"
	end
	return "Locked"
end

-- The rebirth-only nurses, in Data order.
function Pure.branchNurses(roster: any): { string }
	local out: { string } = {}
	for _, nurseId in ordered(roster) do
		if row(roster, nurseId).Source ~= nil then
			table.insert(out, nurseId)
		end
	end
	return out
end
-- PURE-END

NursePanel.Pure = Pure -- for tests/NurseUI.spec

------------------------------------------------------------------------------------------------------------------
-- Look helpers
------------------------------------------------------------------------------------------------------------------

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function textLimit(label: TextLabel | TextButton, max: number, min: number?)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min or 9
	limit.Parent = label
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in props do
		if key ~= "Parent" then
			(f :: any)[key] = value
		end
	end
	f.Parent = props.Parent
	return f
end

local function childOf(parent: Instance, name: string, class: string): Instance?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA(class) then found else nil
end

-- The shape outline Kit draws round a button (not the Contextual one round its text).
local function borderOf(gui: Instance): UIStroke?
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			return child
		end
	end
	return nil
end

local function padButton(button: GuiObject, x: number, y: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, x)
	pad.PaddingRight = UDim.new(0, x)
	pad.PaddingTop = UDim.new(0, y)
	pad.PaddingBottom = UDim.new(0, y)
	pad.Parent = button
end

-- A tab in its rarity's colour: a pale tint while it waits, full candy with outlined text when it's open.
local function paintTab(button: TextButton, selected: boolean, color: Color3)
	button.BackgroundColor3 = if selected then Kit.lighten(color, 0.08) else Kit.lighten(color, 0.78)
	local border = borderOf(button)
	if border then
		border.Color = Theme.Colors.Outline
		border.Thickness = if selected then Theme.Size.StrokeLarge else Theme.Size.Stroke
	end
	local caption = childOf(button, "Caption", "TextLabel") :: TextLabel?
	if caption then
		caption.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
		Kit.outline(caption, 2).Enabled = selected
	end
end

-- A button's colour (and its text style) after it was made: Kit.button picks them from its Kind once.
local function paint(button: TextButton, color: Color3, light: boolean)
	local fill = if light then color else Kit.lighten(color, 0.08)
	button.BackgroundColor3 = fill
	button:SetAttribute("KitColor", fill)
	button.TextColor3 = if light then Theme.Colors.Ink else Theme.Colors.OnColor
	local outline = childOf(button, "TextOutline", "UIStroke") :: UIStroke?
	if outline then
		outline.Enabled = not light
	end
end

-- The strip's view buttons: full candy when it's the view you're on, a pale tint otherwise.
local function paintMode(button: TextButton, selected: boolean)
	paint(button, if selected then ACCENT else Kit.lighten(ACCENT, 0.78), not selected)
	local border = borderOf(button)
	if border then
		border.Thickness = if selected then Theme.Size.StrokeLarge else Theme.Size.Stroke
	end
end

-- A nurse cap in the rarity's colour, tipped on the portrait's head (the 3D nurses wear the same).
local function addCap(portrait: Frame, color: Color3)
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.fromScale(0.37, 0.25)
	cap.Size = UDim2.fromScale(0.3, 0.13)
	cap.Rotation = -16
	cap.BackgroundColor3 = color
	cap.BorderSizePixel = 0
	cap.ZIndex = 7
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = cap
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Outline
	stroke.Thickness = 2
	stroke.Parent = cap
	local cross = Kit.label({
		Name = "Cross",
		Text = "✚",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 1),
		ZIndex = 7,
		Parent = cap,
	})
	cross.TextColor3 = Theme.Colors.OnColor
	cap.Parent = portrait
end

-- A pill of text on a pale tint ("🛎️ ×2 +10% 💰"), sized to its words.
local function chip(parent: Instance, order: number, text: string, color: Color3): Frame
	local pill = frame({
		Name = "Chip" .. order,
		LayoutOrder = order,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	Kit.corner(pill, 18)
	Kit.stroke(pill, Theme.Colors.Outline, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = pill
	Kit.label({
		Name = "Text",
		Text = text,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		Parent = pill,
	})
	return pill
end

local function clearGui(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------------------------------------------

type Card = {
	Id: string,
	Rarity: string,
	Color: Color3,
	Frame: Frame,
	Face: Frame,
	Name: TextLabel,
	Info: TextLabel,
	Hint: TextLabel,
	Team: TextButton,
	Claim: TextButton,
	Duty: TextLabel,
	Ribbon: TextLabel,
	Shown: string, -- "Unseen" | "Seen" | "Hired": which face is drawn now
	StopFrame: (() -> ())?,
}

type Page = {
	Id: string, -- a rarity, or "Branch"
	Color: Color3,
	Frame: ScrollingFrame,
	Tab: TextButton,
	Count: TextLabel,
	Fill: Frame,
	Reward: Frame?,
	RewardText: TextLabel?,
	Badge: Frame?,
	BadgeIcon: TextLabel?,
	Rays: Frame?,
	Claimed: boolean,
	Odds: TextButton?,
	Cards: { Card },
}

type TeamCard = {
	Id: string,
	Frame: Frame,
	Face: Frame,
	LevelBadge: TextLabel,
	Status: TextLabel,
	Name: TextLabel,
	XpFill: Frame,
	XpText: TextLabel,
	Specialty: TextLabel,
	Ability: TextLabel,
	RingHolder: Frame,
	RingIcon: TextLabel,
	Ring: (number) -> (),
	Fraction: number,
	FiredAt: number?,
	Job: TextButton,
	Sell: TextButton,
	List: TextButton,
	Stays: TextLabel,
	Ribbon: TextLabel,
	Resting: boolean,
	Shown: number, -- the XP fraction drawn now
	Stops: { () -> () },
}

type Stamp = { NurseId: string, Kind: string, Level: number? }

function NursePanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local T = Pure.TEXT
	local player = Players.LocalPlayer
	local rarityOrder: { string } = data.Rarities.Order

	local fresh: { [string]: string } = {} -- news since the panel was last opened
	local listed: { [string]: boolean } = {} -- your nurses on the Market (MarketNews / NurseNews Listed)
	local marketAsked = false
	local busy = false
	local view = "" -- "Team" | "Branch" | a rarity: what the panel shows
	local lastPage = "" -- the Journal page shown last (📔 Journal goes back to it)

	local stationIcons: { [string]: string } = {}
	if type(data.Stations) == "table" and type(data.Stations.Order) == "table" then
		for _, stationId in data.Stations.Order do
			local station = rawget(data.Stations, stationId)
			if type(station) == "table" and type(station.Icon) == "string" then
				stationIcons[stationId] = station.Icon
			end
		end
	end
	local stationDepts = if type(data.Departments) == "table" then data.Departments.Stations else nil

	local function rarityInfo(rarity: string): any
		return rawget(data.Rarities, rarity) or rawget(data.Rarities, "Common")
	end

	local function nightRush(): boolean
		return BeltPure.nightRush(Workspace:GetAttribute("NightRush"), Workspace:GetAttribute("IsNight"))
	end

	local function rebirthsOf(state: Types.Snapshot): number
		local rebirth = (state :: any).Rebirth
		return if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
	end

	local function levelCapOf(state: Types.Snapshot): number
		return NurseLogic.levelCap(rebirthsOf(state), cfg)
	end

	local function rosterOf(state: Types.Snapshot): RosterView
		return Pure.roster(state.Nurses, rebirthsOf(state), cfg, data.Nurses)
	end

	local function myPlot(): Instance?
		local index = player:GetAttribute("PlotIndex")
		local clinics = Workspace:FindFirstChild("Clinics")
		if type(index) ~= "number" or not clinics then
			return nil
		end
		return clinics:FindFirstChild("Plot_" .. index)
	end

	local modal = Hud.modal(ctx, {
		Name = "Nurses",
		Title = T.TitleJournal,
		Accent = ACCENT,
		MaxSize = Vector2.new(780, 620),
	})

	--------------------------------------------------------------------------------------------------------------
	-- The header's completion pill
	--------------------------------------------------------------------------------------------------------------
	local title = modal.Panel:FindFirstChild("Title")
	local titleLabel: TextLabel? = if title and title:IsA("TextLabel") then title :: TextLabel else nil
	if titleLabel then
		titleLabel.Size = UDim2.new(1, -(SLOT + Theme.Size.Gap + PILL_WIDTH + Theme.Size.Gap), 0, SLOT)
		titleLabel.TextScaled = true
		titleLabel.TextWrapped = false
		textLimit(titleLabel, Theme.TextSize.Title)
	end
	local pill = frame({
		Name = "Completion",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(SLOT + Theme.Size.Gap), 0, 8),
		Size = UDim2.fromOffset(PILL_WIDTH, 40),
		BackgroundColor3 = Theme.Colors.Paper,
		ZIndex = 2,
		Parent = modal.Panel,
	})
	Kit.corner(pill, 20)
	Kit.stroke(pill, Theme.Colors.Outline, Theme.Size.Stroke)
	pill.ClipsDescendants = true
	local pillFill = frame({
		Name = "Fill",
		BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.05),
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
		Parent = pill,
	})
	Kit.corner(pillFill, 20)
	Palette.candyGradient(pillFill)
	local pillText = Kit.label({
		Name = "Percent",
		Text = "📔 0%",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -14, 1, -10),
		ZIndex = 3,
		Parent = pill,
	})
	textLimit(pillText, 24)

	--------------------------------------------------------------------------------------------------------------
	-- The strip: the two views, then the Agency and the Market
	--------------------------------------------------------------------------------------------------------------
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, 0, 0, STRIP_HEIGHT)
	strip.CanvasSize = UDim2.new()
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 0
	strip.Selectable = false
	strip.Parent = modal.Body
	local stripList = Kit.list(strip, Enum.FillDirection.Horizontal, 8)
	stripList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingLeft = UDim.new(0, 4)
	stripPad.PaddingRight = UDim.new(0, 4)
	stripPad.Parent = strip

	local function stripButton(name: string, order: number, kind: string, text: string, width: number): TextButton
		local button = Kit.button({
			Name = name,
			Kind = kind,
			Text = text,
			TextScaled = true,
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, SLOT),
			Parent = strip,
		})
		padButton(button, 10, 12)
		textLimit(button, Theme.TextSize.Body, 12)
		return button
	end
	local teamTab = stripButton("TeamView", 1, "Cyan", T.TitleTeam, MODE_WIDTH)
	local journalTab = stripButton("JournalView", 2, "Cyan", T.Journal, MODE_WIDTH)
	local agencyButton = stripButton("Agency", 3, "Purple", T.Agency, LINK_WIDTH)
	local marketButton = stripButton("Market", 4, "Pink", T.Market, LINK_WIDTH)
	agencyButton.Activated:Connect(function()
		ctx.fire("Open", "Agency")
	end)
	marketButton.Activated:Connect(function()
		ctx.fire("Open", "Market")
	end)

	--------------------------------------------------------------------------------------------------------------
	-- The Journal: tabs and pages
	--------------------------------------------------------------------------------------------------------------
	local lower = frame({
		Name = "Journal",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, STRIP_HEIGHT + 6),
		Size = UDim2.new(1, 0, 1, -(STRIP_HEIGHT + 6)),
		Parent = modal.Body,
	})
	local tabColumn = Instance.new("ScrollingFrame")
	tabColumn.Name = "Tabs"
	tabColumn.BackgroundTransparency = 1
	tabColumn.BorderSizePixel = 0
	tabColumn.Size = UDim2.new(0, TAB_WIDTH + 10, 1, 0) -- room for the selected tab's thick outline
	tabColumn.CanvasSize = UDim2.new()
	tabColumn.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabColumn.ScrollBarThickness = 0
	tabColumn.Selectable = false
	tabColumn.Parent = lower
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 5)
	tabPad.PaddingBottom = UDim.new(0, 5)
	tabPad.Parent = tabColumn

	local pagesArea = frame({
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TAB_WIDTH + 10 + Theme.Size.Gap, 0),
		Size = UDim2.new(1, -(TAB_WIDTH + 10 + Theme.Size.Gap), 1, 0),
		Parent = lower,
	})

	local pages: { [string]: Page } = {}
	local pageOrder: { string } = {}
	local cardsById: { [string]: Card } = {}
	local render: (state: Types.Snapshot) -> ()
	local showView: (id: string) -> ()
	local claimGift: (button: GuiObject?) -> ()
	local popTeamCard: (nurseId: string) -> ()

	local function newCard(parent: Instance, order: number, nurseId: string, rarity: string, color: Color3): Card
		local card = frame({
			Name = nurseId,
			LayoutOrder = order,
			BackgroundColor3 = UNSEEN_FILL,
			Parent = parent,
		})
		Kit.corner(card, 16)
		local face = frame({
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 1, -CARD_FIXED),
			BackgroundColor3 = UNSEEN_FACE,
			Parent = card,
		})
		Kit.corner(face, 12)
		local name = Kit.label({
			Name = "NurseName",
			Text = "???",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + 20)),
			Size = UDim2.new(1, -10, 0, 22),
			Parent = card,
		})
		textLimit(name, 20)
		local info = Kit.label({
			Name = "Info",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4)),
			Size = UDim2.new(1, -10, 0, 20),
			Parent = card,
		})
		textLimit(info, 18)
		local hint = Kit.label({
			Name = "Hint",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			BackgroundColor3 = Theme.Colors.Card,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Parent = card,
		})
		Kit.corner(hint, 12)
		padButton(hint, 6, 14)
		textLimit(hint, 20)
		local teamButton = Kit.button({
			Name = "Team",
			Kind = "Quiet",
			Text = T.SeeTeam,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Visible = false,
			Parent = card,
		})
		padButton(teamButton, 8, 14)
		local claimButton = Kit.button({
			Name = "Claim",
			Kind = "Good",
			Text = T.Claim,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Visible = false,
			Parent = card,
		})
		padButton(claimButton, 8, 14)
		local duty = Kit.label({
			Name = "OnDuty",
			Text = "✅",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -4),
			Size = UDim2.fromOffset(28, 28),
			Visible = false,
			ZIndex = 4,
			Parent = card,
		})
		-- A red "NEW!" sticker, tipped at an angle, on news you haven't opened yet.
		local ribbon = Kit.label({
			Name = "New",
			Text = T.New,
			TextSize = Theme.TextSize.Small,
			TextWrapped = false,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.fromOffset(58, 26),
			Rotation = -8,
			Visible = false,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(ribbon, 13)
		Kit.stroke(ribbon, Theme.Colors.Outline, 2.5)

		local entry: Card = {
			Id = nurseId,
			Rarity = rarity,
			Color = color,
			Frame = card,
			Face = face,
			Name = name,
			Info = info,
			Hint = hint,
			Team = teamButton,
			Claim = claimButton,
			Duty = duty,
			Ribbon = ribbon,
			Shown = "",
			StopFrame = nil,
		}
		teamButton.Activated:Connect(function()
			showView("Team")
			render(ctx.State)
			popTeamCard(nurseId)
		end)
		claimButton.Activated:Connect(function()
			claimGift(claimButton)
		end)
		return entry
	end

	-- Unseen: a flat grey card, a soft outline and a dark silhouette. Seen: the rarity frame, the creature greyed
	-- out. Hired: a white card in its rarity frame, the creature in full colour on its rarity's tint, with a cap.
	local function setFace(card: Card, look: any, shown: string)
		if card.Shown == shown then
			return
		end
		card.Shown = shown
		local face = card.Face
		face:ClearAllChildren()
		Kit.corner(face, 12)
		local dark = shown == "Unseen"
		local portrait = Hud.portrait(look, dark)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		if not dark then
			addCap(portrait, card.Color)
		end

		local stop = card.StopFrame
		if stop then
			stop()
			card.StopFrame = nil
		end
		local plain = card.Frame:FindFirstChild("Plain")
		if plain then
			plain:Destroy()
		end
		if dark then
			local stroke = Kit.stroke(card.Frame, Theme.Colors.Outline, 2)
			stroke.Name = "Plain"
			stroke.Transparency = 0.6
			card.Frame.BackgroundColor3 = UNSEEN_FILL
			face.BackgroundColor3 = UNSEEN_FACE
			card.Name.TextColor3 = Theme.Colors.InkSoft
			return
		end
		card.StopFrame = Kit.rarityFrame(card.Frame, card.Rarity)
		card.Frame.BackgroundColor3 = Theme.Colors.Paper
		card.Name.TextColor3 = Theme.Colors.Ink
		if shown == "Seen" then
			local frameStroke = card.Frame:FindFirstChild("RarityFrame")
			if frameStroke and frameStroke:IsA("UIStroke") then
				frameStroke.Transparency = 0.45
			end
			face.BackgroundColor3 = SEEN_FACE
			-- Greyed out: a grey veil over the creature (a sibling above the portrait).
			local veil = frame({
				Name = "Veil",
				BackgroundColor3 = Theme.Colors.Disabled,
				BackgroundTransparency = 0.45,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 8,
				Parent = face,
			})
			Kit.corner(veil, 12)
		else
			face.BackgroundColor3 = Kit.lighten(card.Color, 0.45)
			Palette.candyGradient(face)
			Kit.stroke(face, Theme.Colors.Outline, 2)
		end
	end

	local function cardGrid(parent: Instance): Frame
		local holder = frame({
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = parent,
		})
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
		layout.CellSize = UDim2.fromOffset(MIN_CARD, MIN_CARD + CARD_FIXED)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 4 on a big screen).
		local function fit()
			local width = holder.AbsoluteSize.X
			if width <= 0 then
				return
			end
			local columns = math.clamp(math.floor((width + CARD_GAP) / (MIN_CARD + CARD_GAP)), 2, 4)
			local cell = math.floor((width - CARD_GAP * (columns - 1)) / columns)
			layout.CellSize = UDim2.fromOffset(cell, math.min(math.floor(cell * 0.62), 110) + CARD_FIXED)
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		return holder
	end

	local function pageScroll(name: string): ScrollingFrame
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
		scroll.Parent = pagesArea
		local list = Kit.list(scroll, Enum.FillDirection.Vertical, 10)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 4) -- scrolling frames clip: keep the outlines whole
		pad.Parent = scroll
		return scroll
	end

	-- A page header's top part: the icon tile, the name (and a note), the count and the progress bar.
	local function headerTop(header: Frame, icon: string, nameText: string, note: string, color: Color3)
		local tile = frame({
			Name = "Tile",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Kit.lighten(color, 0.08),
			Parent = header,
		})
		Kit.corner(tile, 12)
		Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
		Palette.candyGradient(tile)
		Kit.gloss(tile, 4)
		Kit.label({
			Name = "Icon",
			Text = icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Parent = tile,
		})
		local name = Kit.label({
			Name = "PageName",
			Text = nameText,
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(60, if note == "" then 14 else 6),
			Size = UDim2.new(1, -60 - 64, 0, 26),
			Parent = header,
		})
		textLimit(name, 24)
		if note ~= "" then
			local noteLabel = Kit.label({
				Name = "Note",
				Text = note,
				TextScaled = true,
				TextColor3 = Theme.Colors.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(60, 33),
				Size = UDim2.new(1, -60 - 64, 0, 18),
				Parent = header,
			})
			textLimit(noteLabel, 16)
		end
		local count = Kit.label({
			Name = "Count",
			Text = "0/0",
			TextScaled = true,
			Outlined = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 14),
			Size = UDim2.fromOffset(56, 26),
			Parent = header,
		})
		textLimit(count, 22)
		local track = frame({
			Name = "Track",
			BackgroundColor3 = Theme.Colors.Paper,
			Position = UDim2.fromOffset(8, 58),
			Size = UDim2.new(1, -16, 0, 14),
			Parent = header,
		})
		Kit.corner(track, 7)
		Kit.stroke(track, Theme.Colors.Outline, 2)
		local fill = frame({
			Name = "Fill",
			BackgroundColor3 = Kit.lighten(color, 0.08),
			Size = UDim2.fromScale(0, 1),
			Parent = track,
		})
		Kit.corner(fill, 7)
		Palette.candyGradient(fill)
		return count, fill
	end

	local function pageHeader(parent: ScrollingFrame, rarity: string, info: any, color: Color3): Page
		local header = frame({
			Name = "Header",
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.new(1, -12, 0, HEADER_HEIGHT),
			LayoutOrder = 1,
			Parent = parent,
		})
		Kit.corner(header, 16)
		Kit.rarityFrame(header, rarity)
		local count, fill = headerTop(header, info.Icon, info.Name, Pure.eventNote(info), color)

		-- The group reward, then the 🎲 odds-now chip.
		local rowTop = 58 + 14 + 8
		local reward = frame({
			Name = "Reward",
			BackgroundColor3 = Theme.Colors.Card,
			Position = UDim2.fromOffset(8, rowTop),
			Size = UDim2.new(1, -(8 + 8 + 8 + ODDS_WIDTH), 0, SLOT),
			Parent = header,
		})
		Kit.corner(reward, 14)
		Kit.stroke(reward, Theme.Colors.Outline, 2)
		local holder = frame({
			Name = "BadgeHolder",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(42, 42),
			Parent = reward,
		})
		local badge = frame({
			Name = "Badge",
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = holder,
		})
		Kit.corner(badge, 21)
		Kit.stroke(badge, Theme.Colors.Outline, Theme.Size.Stroke)
		local decor = rawget(data.Decor, info.Journal and info.Journal.Decor or "")
		local badgeIcon = Kit.label({
			Name = "Icon",
			Text = if decor then decor.Icon else "🎁",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = badge,
		})
		local rewardText = Kit.label({
			Name = "Text",
			Text = "🎁 " .. Pure.rewardText(info, if decor then decor.Icon else nil),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(56, 8),
			Size = UDim2.new(1, -62, 1, -16),
			Parent = reward,
		})
		textLimit(rewardText, 22)
		local odds = Kit.button({
			Name = "Odds",
			Kind = "Purple",
			Text = "🎲",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, rowTop),
			Size = UDim2.fromOffset(ODDS_WIDTH, SLOT),
			Parent = header,
		})
		padButton(odds, 8, 12)
		odds.Activated:Connect(function()
			ctx.fire("Open", "NurseOdds")
		end)

		return {
			Id = rarity,
			Color = color,
			Frame = parent,
			Tab = nil :: any,
			Count = count,
			Fill = fill,
			Reward = reward,
			RewardText = rewardText,
			Badge = badge,
			BadgeIcon = badgeIcon,
			Rays = nil,
			Claimed = false,
			Odds = odds,
			Cards = {},
		}
	end

	local function addTab(page: Page, order: number, icon: string, total: number)
		local tab = Kit.iconButton({
			Name = "Tab_" .. page.Id,
			Icon = icon,
			Caption = "0/" .. total,
			LayoutOrder = order,
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_WIDTH),
			Parent = tabColumn,
		})
		local caption = childOf(tab, "Caption", "TextLabel") :: TextLabel?
		if caption then
			caption.Font = Theme.DisplayFont -- the count is a number: chunky
		end
		tab.Activated:Connect(function()
			showView(page.Id)
			render(ctx.State)
		end)
		page.Tab = tab
		pages[page.Id] = page
		table.insert(pageOrder, page.Id)
	end

	for order, rarity in rarityOrder do
		local info = rarityInfo(rarity)
		local color = hexColor(info.Color, Theme.Colors.Quiet)
		local scroll = pageScroll(rarity)
		local page = pageHeader(scroll, rarity, info, color)
		local grid = cardGrid(scroll)
		local index = 0
		for _, nurseId in data.Nurses.Order do
			local nurse = rawget(data.Nurses, nurseId)
			if nurse and nurse.Rarity == rarity and nurse.Source == nil then
				index += 1
				local card = newCard(grid, index, nurseId, rarity, color)
				table.insert(page.Cards, card)
				cardsById[nurseId] = card
			end
		end
		addTab(page, order, info.Icon, index)
	end

	-- 🏢 The rebirth-only nurses: their own page, outside every rarity group and the Journal %.
	local branchIds = Pure.branchNurses(data.Nurses)
	if #branchIds > 0 then
		local color = Theme.Colors.Purple
		local scroll = pageScroll("Branch")
		local header = frame({
			Name = "Header",
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.new(1, -12, 0, BRANCH_HEADER_HEIGHT),
			LayoutOrder = 1,
			Parent = scroll,
		})
		Kit.corner(header, 16)
		Kit.stroke(header, Theme.Colors.Outline, Theme.Size.Stroke)
		local count, fill = headerTop(header, T.BranchTab, T.BranchName, T.BranchNote, color)
		local page: Page = {
			Id = "Branch",
			Color = color,
			Frame = scroll,
			Tab = nil :: any,
			Count = count,
			Fill = fill,
			Reward = nil,
			RewardText = nil,
			Badge = nil,
			BadgeIcon = nil,
			Rays = nil,
			Claimed = false,
			Odds = nil,
			Cards = {},
		}
		local grid = cardGrid(scroll)
		for index, nurseId in branchIds do
			local nurse = rawget(data.Nurses, nurseId)
			local card = newCard(grid, index, nurseId, nurse.Rarity, hexColor(rarityInfo(nurse.Rarity).Color, color))
			table.insert(page.Cards, card)
			cardsById[nurseId] = card
		end
		addTab(page, #rarityOrder + 1, T.BranchTab, #branchIds)
	end
	local tabs = {}
	for _, id in pageOrder do
		table.insert(tabs, pages[id].Tab)
	end
	Hud.fitTabs(tabColumn, tabs, 8)

	--------------------------------------------------------------------------------------------------------------
	-- The Team view
	--------------------------------------------------------------------------------------------------------------
	local teamScroll = Instance.new("ScrollingFrame")
	teamScroll.Name = "Team"
	teamScroll.BackgroundTransparency = 1
	teamScroll.BorderSizePixel = 0
	teamScroll.Position = UDim2.fromOffset(0, STRIP_HEIGHT + 6)
	teamScroll.Size = UDim2.new(1, 0, 1, -(STRIP_HEIGHT + 6))
	teamScroll.CanvasSize = UDim2.new()
	teamScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	teamScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	teamScroll.ScrollBarThickness = 8
	teamScroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	teamScroll.Selectable = false
	teamScroll.Visible = false
	teamScroll.Parent = modal.Body
	local teamList = Kit.list(teamScroll, Enum.FillDirection.Vertical, 10)
	teamList.VerticalAlignment = Enum.VerticalAlignment.Top
	teamList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local teamPad = Instance.new("UIPadding")
	teamPad.PaddingTop = UDim.new(0, 4)
	teamPad.PaddingBottom = UDim.new(0, 10)
	teamPad.PaddingLeft = UDim.new(0, 4)
	teamPad.PaddingRight = UDim.new(0, 14)
	teamPad.Parent = teamScroll

	-- The roster, resting, and team chips.
	local summary = frame({
		Name = "Summary",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = teamScroll,
	})
	local summaryList = Kit.list(summary, Enum.FillDirection.Horizontal, 8)
	summaryList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	summaryList.VerticalAlignment = Enum.VerticalAlignment.Top
	summaryList.Wraps = true

	-- The gift row: a rebirth-only nurse waiting for a roster place.
	local giftRow = frame({
		Name = "Gift",
		LayoutOrder = 2,
		BackgroundColor3 = Kit.lighten(Theme.Colors.Good, 0.82),
		Size = UDim2.new(1, 0, 0, 76),
		Visible = false,
		Parent = teamScroll,
	})
	Kit.corner(giftRow, 16)
	Kit.stroke(giftRow, Theme.Colors.Outline, Theme.Size.Stroke)
	local giftFace = frame({
		Name = "Face",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.Paper,
		Parent = giftRow,
	})
	Kit.corner(giftFace, 14)
	local giftText = Kit.label({
		Name = "Text",
		Text = T.GiftHead,
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(76, 10),
		Size = UDim2.new(1, -(76 + 150 + 12), 1, -20),
		Parent = giftRow,
	})
	textLimit(giftText, Theme.TextSize.Body)
	local giftClaim = Kit.button({
		Name = "Claim",
		Kind = "Good",
		Text = T.Claim,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(150, SLOT),
		Parent = giftRow,
	})
	textLimit(giftClaim, Theme.TextSize.Body)
	giftClaim.Activated:Connect(function()
		claimGift(giftClaim)
	end)
	local giftShown = ""

	-- No nurses yet: where they come from.
	local emptyCard = frame({
		Name = "Empty",
		LayoutOrder = 3,
		BackgroundColor3 = Theme.Colors.Card,
		Size = UDim2.new(1, 0, 0, 8 + 40 + 8 + SLOT + 10),
		Visible = false,
		Parent = teamScroll,
	})
	Kit.corner(emptyCard, 16)
	Kit.stroke(emptyCard, Theme.Colors.Outline, 2)
	local emptyText = Kit.label({
		Name = "Text",
		Text = T.Empty,
		TextScaled = true,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 40),
		Parent = emptyCard,
	})
	textLimit(emptyText, Theme.TextSize.Body)
	local emptyAgency = Kit.button({
		Name = "Agency",
		Kind = "Purple",
		Text = T.Agency,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8 + 40 + 8),
		Size = UDim2.fromOffset(200, SLOT),
		Parent = emptyCard,
	})
	textLimit(emptyAgency, Theme.TextSize.Body)
	emptyAgency.Activated:Connect(function()
		ctx.fire("Open", "Agency")
	end)

	local teamGrid = frame({
		Name = "Cards",
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = teamScroll,
	})
	local teamLayout = Instance.new("UIGridLayout")
	teamLayout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	teamLayout.CellSize = UDim2.fromOffset(320, TEAM_CARD_HEIGHT)
	teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
	teamLayout.Parent = teamGrid
	local function fitTeam()
		local width = teamGrid.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local columns = if width >= TEAM_TWO_UP then 2 else 1
		teamLayout.CellSize =
			UDim2.fromOffset(math.floor((width - CARD_GAP * (columns - 1)) / columns), TEAM_CARD_HEIGHT)
	end
	teamGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTeam)
	fitTeam()

	local teamCards: { [string]: TeamCard } = {}
	local teamKey = ""
	local summaryKey = ""
	local openPicker: (nurseId: string) -> ()

	local function newTeamCard(nurseId: string, order: number): TeamCard?
		local nurse = rawget(data.Nurses, nurseId)
		if type(nurse) ~= "table" then
			return nil
		end
		local color = hexColor(rarityInfo(nurse.Rarity).Color, Theme.Colors.Quiet)
		local stops: { () -> () } = {}
		local card = frame({
			Name = nurseId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.Colors.Paper,
			Parent = teamGrid,
		})
		Kit.corner(card, 16)
		table.insert(stops, Kit.rarityFrame(card, nurse.Rarity))

		local face = frame({
			Name = "Face",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(FACE, FACE),
			BackgroundColor3 = Kit.lighten(color, 0.45),
			Parent = card,
		})
		Kit.corner(face, 12)
		Palette.candyGradient(face)
		Kit.stroke(face, Theme.Colors.Outline, 2)
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		addCap(portrait, color)
		local levelBadge = Kit.label({
			Name = "Level",
			Text = "Lv 1",
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = Kit.lighten(ACCENT, 0.05),
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 6),
			Size = UDim2.new(1, -10, 0, 22),
			ZIndex = 9,
			Parent = face,
		})
		Kit.corner(levelBadge, 11)
		Kit.stroke(levelBadge, Theme.Colors.Outline, 2)
		padButton(levelBadge, 4, 2)
		local status = Kit.label({
			Name = "Status",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 6, 0, -6),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 9,
			Parent = face,
		})

		local name = Kit.label({
			Name = "NurseName",
			Text = nurse.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(LEFT, 8),
			Size = UDim2.new(1, -(LEFT + RING + 16), 0, 24),
			Parent = card,
		})
		textLimit(name, 22)
		local track = frame({
			Name = "Xp",
			BackgroundColor3 = Theme.Colors.Card,
			Position = UDim2.fromOffset(LEFT, 36),
			Size = UDim2.new(1, -(LEFT + RING + 16), 0, 18),
			Parent = card,
		})
		Kit.corner(track, 9)
		Kit.stroke(track, Theme.Colors.Outline, 2)
		track.ClipsDescendants = true
		local xpFill = frame({
			Name = "Fill",
			BackgroundColor3 = Kit.lighten(Theme.Colors.Good, 0.05),
			Size = UDim2.fromScale(0, 1),
			Parent = track,
		})
		Kit.corner(xpFill, 9)
		Palette.candyGradient(xpFill)
		local xpText = Kit.label({
			Name = "Text",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.Ink,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = track,
		})
		textLimit(xpText, 14)

		-- The specialty and the ability, side by side under the bar.
		local chipsLeft = LEFT
		local chipsRight = RING + 16
		local specialty = Kit.label({
			Name = "Specialty",
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Theme.Colors.Card,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(chipsLeft, 58),
			Size = UDim2.new(0.5, -(chipsLeft + chipsRight) / 2 - 3, 0, 24),
			Parent = card,
		})
		Kit.corner(specialty, 12)
		padButton(specialty, 8, 3)
		textLimit(specialty, 16)
		local ability = Kit.label({
			Name = "Ability",
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Theme.Colors.Card,
			BackgroundTransparency = 0,
			Position = UDim2.new(0.5, (chipsLeft - chipsRight) / 2 + 3, 0, 58),
			Size = UDim2.new(0.5, -(chipsLeft + chipsRight) / 2 - 3, 0, 24),
			Parent = card,
		})
		Kit.corner(ability, 12)
		padButton(ability, 8, 3)
		textLimit(ability, 16)

		-- The ability ring: fills as it recharges (never seconds); full = ready.
		local ringHolder = frame({
			Name = "AbilityRing",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(RING, RING),
			BackgroundColor3 = Theme.Colors.Paper,
			Parent = card,
		})
		Kit.corner(ringHolder, RING)
		local setRing = Kit.ring(ringHolder, ACCENT)
		local abilityDef = rawget(data.Abilities, nurse.Ability or "")
		local ringIcon = Kit.label({
			Name = "Icon",
			Text = if abilityDef then abilityDef.Icon else "✨",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.56, 0.56),
			ZIndex = 6,
			Parent = ringHolder,
		})

		-- The foot: the job button, then Sell and List (or "🏢 Stays with you").
		local footTop = 8 + FACE + 8
		local job = Kit.button({
			Name = "Job",
			Kind = "Secondary",
			Text = "",
			TextScaled = true,
			Position = UDim2.fromOffset(8, footTop),
			Size = UDim2.new(1, -(16 + 2 * (ACTION_WIDTH + 6)), 0, SLOT),
			Parent = card,
		})
		padButton(job, 10, 12)
		textLimit(job, 22, 11)
		local sell = Kit.button({
			Name = "Sell",
			Kind = "Cash",
			Text = T.Sell,
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(8 + ACTION_WIDTH + 6), 0, footTop),
			Size = UDim2.fromOffset(ACTION_WIDTH, SLOT),
			Parent = card,
		})
		padButton(sell, 8, 12)
		textLimit(sell, 20, 11)
		local listButton = Kit.button({
			Name = "List",
			Kind = "Pink",
			Text = T.List,
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, footTop),
			Size = UDim2.fromOffset(ACTION_WIDTH, SLOT),
			Parent = card,
		})
		padButton(listButton, 8, 12)
		textLimit(listButton, 20, 11)
		local stays = Kit.label({
			Name = "Stays",
			Text = T.Stays,
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			BackgroundColor3 = Theme.Colors.Card,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, footTop),
			Size = UDim2.fromOffset(2 * ACTION_WIDTH + 6, SLOT),
			Visible = false,
			Parent = card,
		})
		Kit.corner(stays, 12)
		padButton(stays, 8, 14)
		textLimit(stays, 20)

		local ribbon = Kit.label({
			Name = "New",
			Text = T.New,
			TextSize = Theme.TextSize.Small,
			TextWrapped = false,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(-6, -8),
			Size = UDim2.fromOffset(64, 26),
			Rotation = -8,
			Visible = false,
			ZIndex = 10,
			Parent = card,
		})
		Kit.corner(ribbon, 13)
		Kit.stroke(ribbon, Theme.Colors.Outline, 2.5)

		local entry: TeamCard = {
			Id = nurseId,
			Frame = card,
			Face = face,
			LevelBadge = levelBadge,
			Status = status,
			Name = name,
			XpFill = xpFill,
			XpText = xpText,
			Specialty = specialty,
			Ability = ability,
			RingHolder = ringHolder,
			RingIcon = ringIcon,
			Ring = setRing,
			Fraction = -1,
			FiredAt = nil,
			Job = job,
			Sell = sell,
			List = listButton,
			Stays = stays,
			Ribbon = ribbon,
			Resting = false,
			Shown = -1,
			Stops = stops,
		}
		job.Activated:Connect(function()
			openPicker(nurseId)
		end)
		sell.Activated:Connect(function()
			if listed[nurseId] then
				ctx.toast(T.UnlistFirst)
				Hud.shake(sell)
				return
			end
			ctx.fire("Sell", nurseId)
		end)
		listButton.Activated:Connect(function()
			if listed[nurseId] then
				ctx.fire("Open", "Market")
			else
				ctx.fire("List", nurseId)
			end
		end)
		return entry
	end

	popTeamCard = function(nurseId: string)
		local card = teamCards[nurseId]
		if card then
			Hud.pop(card.Frame, 1.08)
			if card.Frame.AbsolutePosition.Y > 0 then
				local offset = card.Frame.AbsolutePosition.Y
					- teamScroll.AbsolutePosition.Y
					+ teamScroll.CanvasPosition.Y
				teamScroll.CanvasPosition = Vector2.new(0, math.max(0, offset - 8))
			end
		end
	end

	local function setXp(card: TeamCard, fraction: number)
		if math.abs(card.Shown - fraction) < 0.001 then
			return
		end
		local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		-- Rolls forward as it fills; a level-up (the bar going back to empty) and reduced motion just set it.
		if card.Shown < 0 or fraction < card.Shown or Kit.reducedMotion() or not modal.isOpen() then
			card.XpFill.Size = target
		else
			TweenService:Create(card.XpFill, Theme.Tween.Fill, { Size = target }):Play()
		end
		card.Shown = fraction
	end

	local function renderTeamCard(card: TeamCard, state: Types.Snapshot, roster: RosterView, order: number)
		local nurse = rawget(data.Nurses, card.Id)
		local entry = if type(state.Nurses) == "table" then (state.Nurses :: any)[card.Id] else nil
		if type(nurse) ~= "table" or type(entry) ~= "table" then
			return
		end
		card.Frame.LayoutOrder = order
		local working = table.find(roster.Working, card.Id) ~= nil
		local resting = not working
		card.Resting = resting
		local cap = levelCapOf(state)
		local xp = Pure.xp(entry, cap)
		card.LevelBadge.Text = "Lv " .. xp.Level
		card.XpText.Text = Pure.xpText(xp)
		card.XpFill.BackgroundColor3 = if xp.Max
			then Kit.lighten(Theme.Colors.Cash, 0.05)
			elseif resting then Theme.Colors.Disabled
			else Kit.lighten(Theme.Colors.Good, 0.05)
		setXp(card, xp.Fraction)
		card.Specialty.Text = Pure.specialtyText(nurse.Specialty, data.Departments)
		card.Ability.Text = Pure.abilityText(nurse.Ability, xp.Level, data.Abilities, cfg)
		card.Job.Text = Pure.jobButton(entry, nurse, state.Level, data.Jobs, resting)
		paint(card.Job, if resting then Theme.Colors.Quiet else Theme.Colors.Secondary, resting)
		card.Frame.BackgroundColor3 = if resting then RESTING_FILL else Theme.Colors.Paper

		local actions = Pure.actions(card.Id, data.Nurses, listed)
		card.Sell.Visible = actions.Sell
		card.List.Visible = actions.List
		card.Stays.Visible = actions.Stays -- in the same place as Sell + List, so the job button keeps its width
		card.List.Text = if actions.Listed then T.Listed else T.List
		paint(card.Sell, if actions.Listed then Theme.Colors.Disabled else Theme.Colors.Cash, false)
		card.Status.Visible = resting or actions.Listed
		card.Status.Text = if resting then "💤" else "🏷️"

		local news = fresh[card.Id]
		card.Ribbon.Visible = news == "Level" or news == "Hired"
		card.Ribbon.Text = if news == "Level" then T.LevelUp .. " Lv " .. xp.Level else T.New
		card.Ribbon.BackgroundColor3 = if news == "Level" then Theme.Colors.Good else Theme.Colors.Dot
	end

	local function renderSummary(state: Types.Snapshot, roster: RosterView)
		local chips = Pure.teamChips(roster.Working, data.Nurses, data.Departments, stationIcons)
		local parts = { roster.Text, roster.RestText }
		for _, teamChip in chips do
			table.insert(parts, teamChip.Text)
		end
		local key = table.concat(parts, "|")
		if key ~= summaryKey then
			summaryKey = key
			clearGui(summary)
			local rosterChip = chip(summary, 1, roster.Text, Kit.lighten(ACCENT, if roster.Full then 0.55 else 0.8))
			Kit.bump(rosterChip)
			if roster.RestText ~= "" then
				chip(summary, 2, roster.RestText, Kit.lighten(Theme.Colors.Disabled, 0.5))
			end
			for index, teamChip in chips do
				chip(summary, 2 + index, teamChip.Text, Kit.lighten(Theme.Colors.Cash, 0.6))
			end
			if #chips == 0 and roster.Owned >= 2 then
				chip(summary, 99, T.TeamHint, Theme.Colors.Card)
			end
		end

		local gift = Pure.gift(state, data.Nurses, cfg)
		giftRow.Visible = gift ~= nil
		if gift and gift.NurseId ~= giftShown then
			giftShown = gift.NurseId
			giftFace:ClearAllChildren()
			Kit.corner(giftFace, 14)
			local nurse = rawget(data.Nurses, gift.NurseId)
			local portrait = Hud.portrait(if nurse then nurse.Look else nil, false)
			portrait.AnchorPoint = Vector2.new(0.5, 0.5)
			portrait.Position = UDim2.fromScale(0.5, 0.5)
			portrait.Size = UDim2.fromScale(0.95, 0.95)
			portrait.Parent = giftFace
		end
		emptyCard.Visible = roster.Owned == 0
	end

	local function renderTeam(state: Types.Snapshot)
		local roster = rosterOf(state)
		renderSummary(state, roster)
		local order: { string } = table.clone(roster.Working)
		for _, nurseId in roster.Resting do
			table.insert(order, nurseId)
		end
		local key = table.concat(order, ",")
		if key ~= teamKey then
			teamKey = key
			-- Keep the cards that are still here; drop the ones that left; make the new ones.
			for nurseId, card in teamCards do
				if not table.find(order, nurseId) then
					for _, stop in card.Stops do
						stop()
					end
					card.Frame:Destroy()
					teamCards[nurseId] = nil
				end
			end
			for index, nurseId in order do
				if not teamCards[nurseId] then
					local card = newTeamCard(nurseId, index)
					if card then
						teamCards[nurseId] = card
					end
				end
			end
		end
		for index, nurseId in order do
			local card = teamCards[nurseId]
			if card then
				renderTeamCard(card, state, roster, index)
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The ability rings (only while the Team view is open)
	--------------------------------------------------------------------------------------------------------------
	local ringToken = 0

	local function updateRings()
		local plot = myPlot()
		local folder = if plot then plot:FindFirstChild("Nurses") else nil
		local now = Workspace:GetServerTimeNow()
		for nurseId, card in teamCards do
			local fraction = 0
			if not card.Resting then
				local model = if folder then folder:FindFirstChild("Nurse_" .. nurseId) else nil
				if model then
					fraction = Pure.ringFraction(
						model:GetAttribute("AbilityReadyAt"),
						model:GetAttribute("AbilityCooldown"),
						now
					)
					local firedAt = model:GetAttribute("AbilityAt")
					if type(firedAt) == "number" then
						if card.FiredAt and firedAt > card.FiredAt then
							Kit.bump(card.RingHolder) -- it just helped (the world sparkle is Feel/HospitalFX's)
						end
						card.FiredAt = firedAt
					end
				else
					fraction = 1 -- no times known yet: abilities fire by themselves, so it's ready
				end
			end
			if math.abs(fraction - card.Fraction) > 0.004 then
				card.Fraction = fraction
				card.Ring(fraction)
			end
			card.RingIcon.TextTransparency = if card.Resting then 0.55 else 0
		end
	end

	local function startRings()
		ringToken += 1
		local mine = ringToken
		task.spawn(function()
			while mine == ringToken and modal.isOpen() and view == "Team" do
				local ok, err = pcall(updateRings)
				if not ok then
					warn("[NursePanel] rings: " .. tostring(err))
					return
				end
				task.wait(RING_STEP)
			end
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Asking the server
	--------------------------------------------------------------------------------------------------------------
	local function ask(button: GuiObject?, remote: RemoteFunction, ...: any): boolean
		if busy then
			return false
		end
		busy = true
		local textButton: TextButton? = if button and button:IsA("TextButton") then button :: TextButton else nil
		local before = if textButton then textButton.Text else ""
		if textButton then
			textButton.Text = T.Busy
		end
		local ok, message = Hud.ask(remote, ...)
		busy = false
		if textButton then
			textButton.Text = before
		end
		if ok then
			if message ~= "" then
				ctx.toast(message)
			end
		else
			ctx.toast(if message ~= "" then message else T.Oops)
			Hud.shake(button)
		end
		render(ctx.State)
		return ok
	end

	claimGift = function(button: GuiObject?)
		local gift = Pure.gift(ctx.State, data.Nurses, cfg)
		if not gift then
			return
		end
		if not gift.Room then
			ctx.toast(T.RosterFull)
			Hud.shake(button)
			return
		end
		if ask(button, ctx.Remotes.ClaimBranchNurse) then
			Hud.sound("Sparkle")
		end
	end

	-- Your listings: the Market tells everyone (MarketNews); ask once in case none came since you joined.
	local function askMarketOnce()
		if marketAsked then
			return
		end
		marketAsked = true
		task.spawn(function()
			local ok, _, payload = Hud.ask(ctx.Remotes.GetMarket)
			if ok and type(payload) == "table" then
				listed = Pure.listedSet(payload, player.UserId)
				if modal.isOpen() then
					render(ctx.State)
				end
			end
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The job picker (a Popup above the panel)
	--------------------------------------------------------------------------------------------------------------
	local picker = Hud.modal(ctx, {
		Name = "NurseJob",
		Title = T.PickJob,
		Accent = ACCENT,
		Layer = "Popup",
		MaxSize = Vector2.new(540, 600),
		Scale = Vector2.new(0.9, 0.94),
	})
	local pickerNote = Kit.label({
		Name = "Boost",
		Text = Pure.boostText(cfg),
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = picker.Body,
	})
	textLimit(pickerNote, 20)
	local pickerList = Instance.new("ScrollingFrame")
	pickerList.Name = "Jobs"
	pickerList.BackgroundTransparency = 1
	pickerList.BorderSizePixel = 0
	pickerList.Position = UDim2.fromOffset(0, 32)
	pickerList.Size = UDim2.new(1, 0, 1, -32)
	pickerList.CanvasSize = UDim2.new()
	pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerList.ScrollingDirection = Enum.ScrollingDirection.Y
	pickerList.ScrollBarThickness = 8
	pickerList.ScrollBarImageColor3 = Theme.Colors.Stroke
	pickerList.Selectable = false
	pickerList.Parent = picker.Body
	local pickerLayout = Kit.list(pickerList, Enum.FillDirection.Vertical, 8)
	pickerLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local pickerPad = Instance.new("UIPadding")
	pickerPad.PaddingTop = UDim.new(0, 3)
	pickerPad.PaddingBottom = UDim.new(0, 6)
	pickerPad.PaddingLeft = UDim.new(0, 3)
	pickerPad.PaddingRight = UDim.new(0, 12)
	pickerPad.Parent = pickerList
	local pickerFor: string? = nil
	local pickerKey = "" -- what the rows show now, so a snapshot with no change doesn't rebuild them

	local function pickerOptions(state: Types.Snapshot, nurseId: string): { JobOption }?
		local nurse = rawget(data.Nurses, nurseId)
		local entry = if type(state.Nurses) == "table" then (state.Nurses :: any)[nurseId] else nil
		if type(nurse) ~= "table" or type(entry) ~= "table" then
			return nil
		end
		local roster = rosterOf(state)
		local resting = table.find(roster.Working, nurseId) == nil
		return Pure.jobOptions(entry, nurse, state.Level, data.Jobs, resting, #roster.Working, roster.Cap, stationDepts)
	end

	local function renderPicker(state: Types.Snapshot)
		local nurseId = pickerFor
		if not nurseId then
			return
		end
		local options = pickerOptions(state, nurseId)
		if not options then
			picker.close() -- the nurse left (sold, or bought from you)
			return
		end
		local parts = { nurseId }
		for _, option in options do
			table.insert(parts, option.Id .. option.State .. option.Caption)
		end
		local key = table.concat(parts, ",")
		if key == pickerKey then
			return
		end
		pickerKey = key
		clearGui(pickerList)
		local first: GuiObject? = nil
		for index, option in options do
			local current = option.State == "Current"
			local closed = option.State == "Closed" or option.State == "Full"
			local button = Kit.button({
				Name = option.Id,
				Kind = "Card",
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, JOB_ROW_HEIGHT),
				Parent = pickerList,
			})
			paint(
				button,
				if current
					then Kit.lighten(ACCENT, 0.6)
					elseif closed then Kit.lighten(Theme.Colors.Disabled, 0.55)
					else Theme.Colors.Paper,
				true
			)
			local tile = frame({
				Name = "Tile",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(50, 50),
				BackgroundColor3 = if closed then Theme.Colors.Disabled else Kit.lighten(ACCENT, 0.08),
				ZIndex = 2,
				Parent = button,
			})
			Kit.corner(tile, 12)
			Kit.stroke(tile, Theme.Colors.Outline, 2.5)
			Kit.label({
				Name = "Icon",
				Text = option.Icon,
				TextScaled = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.76, 0.76),
				ZIndex = 3,
				Parent = tile,
			})
			local name = Kit.label({
				Name = "JobName",
				Text = option.Name .. (if option.Boost then " ⭐" else ""),
				TextScaled = true,
				Font = Theme.DisplayFont,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(68, 6),
				Size = UDim2.new(1, -(68 + 96), 0, 28),
				ZIndex = 2,
				Parent = button,
			})
			textLimit(name, 22)
			local words = Kit.label({
				Name = "Words",
				Text = option.Text,
				TextScaled = true,
				TextColor3 = Theme.Colors.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(68, 36),
				Size = UDim2.new(1, -(68 + 96), 0, 24),
				ZIndex = 2,
				Parent = button,
			})
			textLimit(words, 18)
			if option.Caption ~= "" then
				local caption = Kit.label({
					Name = "Caption",
					Text = option.Caption,
					TextScaled = true,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(86, 32),
					ZIndex = 2,
					Parent = button,
				})
				textLimit(caption, 20)
			end
			button.Activated:Connect(function()
				if pickerFor ~= nurseId then
					return
				end
				if option.State == "Current" then
					picker.close()
					return
				end
				local message = Pure.jobMessage(option)
				if message then
					ctx.toast(message)
					Hud.shake(button)
					return
				end
				if ask(nil, ctx.Remotes.SetJob, nurseId, option.Id) then
					picker.close()
					local card = teamCards[nurseId]
					if card then
						Kit.bump(card.Job)
					end
				end
			end)
			if not first or current then
				first = button
			end
		end
		picker.Focus = first
	end

	openPicker = function(nurseId: string)
		pickerFor = nurseId
		pickerKey = ""
		renderPicker(ctx.State)
		if pickerFor == nurseId then
			picker.open()
		end
	end

	ctx.on("ModalClosed", function(name: any)
		if name == "NurseJob" then
			pickerFor = nil
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Switching views
	--------------------------------------------------------------------------------------------------------------
	showView = function(id: string)
		if id == "Team" then
			view = "Team"
			lower.Visible = false
			teamScroll.Visible = true
			if titleLabel then
				titleLabel.Text = T.TitleTeam
			end
			paintMode(teamTab, true)
			paintMode(journalTab, false)
			modal.Focus = teamTab
			askMarketOnce()
			if modal.isOpen() then
				startRings()
			end
			return
		end
		local page = pages[id]
		if not page then
			return
		end
		view = id
		lastPage = id
		ringToken += 1 -- the rings sleep while the Journal shows
		lower.Visible = true
		teamScroll.Visible = false
		if titleLabel then
			titleLabel.Text = T.TitleJournal
		end
		paintMode(teamTab, false)
		paintMode(journalTab, true)
		for pageId, p in pages do
			local selected = pageId == id
			p.Frame.Visible = selected
			paintTab(p.Tab, selected, p.Color)
		end
		modal.Focus = page.Tab
	end

	teamTab.Activated:Connect(function()
		showView("Team")
		render(ctx.State)
	end)
	journalTab.Activated:Connect(function()
		showView(if pages[lastPage] then lastPage else Pure.openView(nil, {}, data.Nurses, rarityOrder, nil))
		render(ctx.State)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Drawing the Journal from the Snapshot
	--------------------------------------------------------------------------------------------------------------
	local function renderCard(card: Card, state: Types.Snapshot, roster: RosterView)
		local nurse = rawget(data.Nurses, card.Id)
		if not nurse then
			return
		end
		local mark = Pure.mark(state.NurseIndex, card.Id)
		local entry = if type(state.Nurses) == "table" then (state.Nurses :: any)[card.Id] else nil
		local owned = type(entry) == "table"
		local branchState = if nurse.Source ~= nil then Pure.branchCard(card.Id, state) else nil
		local shown = if owned or mark == "Hired" then "Hired" elseif branchState == "Pending" then "Seen" else mark
		setFace(card, nurse.Look, shown)
		local news = fresh[card.Id]
		card.Ribbon.Visible = news == "Seen" or news == "Hired"
		local working = table.find(roster.Working, card.Id) ~= nil
		card.Duty.Visible = owned
		card.Duty.Text = if working then "✅" else "💤"
		card.Team.Visible = owned
		card.Claim.Visible = not owned and branchState == "Pending"
		card.Hint.Visible = not card.Team.Visible and not card.Claim.Visible
		if owned then
			local level = if type(entry.Level) == "number" then entry.Level else 1
			local jobId = if working then JobsLogic.effective(entry.Job, nurse.Role, state.Level, data.Jobs) else nil
			local job = if jobId then rawget(data.Jobs, jobId) else nil
			local stat = if jobId then BeltPure.statText(jobId, nurse.Rarity, level, cfg) else ""
			card.Name.Text = nurse.Name
			card.Info.Text = (if job then job.Icon elseif working then "" else "💤")
				.. " "
				.. Pure.levelText(entry, levelCapOf(state))
				.. (if stat ~= "" then "  " .. stat else "")
			return
		end
		if branchState ~= nil then
			card.Name.Text = if branchState == "Locked" then "???" else nurse.Name
			card.Info.Text = ""
			card.Hint.Text = "🏢 R" .. tostring(nurse.Rebirths or "?")
			return
		end
		local price = BeltLogic.price(cfg, nurse.Rarity, state.Level)
		card.Hint.Text = Pure.hint(mark, rarityInfo(nurse.Rarity), price)
		if mark == "Unseen" then
			card.Name.Text = "???"
			card.Info.Text = ""
		else
			local role = rawget(data.Jobs, nurse.Role)
			card.Name.Text = nurse.Name
			card.Info.Text = (if role then role.Icon .. " " .. role.Name else Pure.ROLE_NAMES[nurse.Role] or "")
		end
	end

	local function renderJournal(state: Types.Snapshot, roster: RosterView)
		local journal = NurseLogic.journal(
			if type(state.NurseIndex) == "table" then state.NurseIndex else {},
			data.Nurses,
			data.Rarities
		)
		local oddsNow = BeltLogic.odds(cfg, nightRush(), Workspace:GetAttribute("GoldenHour") == true)
		local claimedSets = if type(state.JournalSets) == "table" then state.JournalSets else {}

		for pageId, page in pages do
			local total, hired, complete = 0, 0, false
			if pageId == "Branch" then
				for _, card in page.Cards do
					total += 1
					if Pure.branchCard(card.Id, state) == "Owned" then
						hired += 1
					end
				end
				complete = total > 0 and hired == total
			else
				local group = journal.Groups[pageId] or { Total = 0, Seen = 0, Hired = 0, Complete = false }
				total, hired, complete = group.Total, group.Hired, group.Complete
			end
			page.Count.Text = hired .. "/" .. total
			page.Fill.Size = UDim2.fromScale(if total > 0 then hired / total else 0, 1)
			local caption = page.Tab:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				caption.Text = if complete then "✅" else hired .. "/" .. total
			end
			local news = false
			for _, card in page.Cards do
				local kind = fresh[card.Id]
				if kind == "Seen" or kind == "Hired" then
					news = true
				end
				renderCard(card, state, roster)
			end
			Kit.setDot(page.Tab, news)
			if page.Odds then
				page.Odds.Text = "🎲 " .. BeltPure.percent(oddsNow[pageId])
			end

			-- Still to earn: a faded icon on white. Earned: ✅, a gold badge on turning rays.
			local badge, reward, rewardText, badgeIcon = page.Badge, page.Reward, page.RewardText, page.BadgeIcon
			if badge and reward and rewardText and badgeIcon then
				local claimed = claimedSets[pageId] == true
				local info = rarityInfo(pageId)
				local decor = rawget(data.Decor, info.Journal and info.Journal.Decor or "")
				rewardText.Text = (if claimed then "✅ " else "🎁 ")
					.. Pure.rewardText(info, if decor then decor.Icon else nil)
				badgeIcon.TextTransparency = if claimed then 0 else 0.5
				badge.BackgroundColor3 = if claimed then Kit.lighten(Theme.Colors.Cash, 0.08) else Theme.Colors.Paper
				reward.BackgroundColor3 = if claimed then Kit.lighten(Theme.Colors.Cash, 0.6) else Theme.Colors.Card
				local holder = badge.Parent
				if claimed and not page.Rays and holder and holder:IsA("GuiObject") then
					page.Rays = Kit.rays(holder, Theme.Colors.Cash)
				end
				local rays = page.Rays
				if rays then
					rays.Visible = claimed
				end
				if claimed and not page.Claimed then
					Kit.bump(badge)
				end
				page.Claimed = claimed
			end
		end
	end

	render = function(state: Types.Snapshot)
		local roster = rosterOf(state)
		local journal = NurseLogic.journal(
			if type(state.NurseIndex) == "table" then state.NurseIndex else {},
			data.Nurses,
			data.Rarities
		)
		pillText.Text = "📔 " .. journal.Percent .. "%"
		pillFill.Size = UDim2.fromScale(math.clamp(journal.Percent / 100, 0, 1), 1)
		teamTab.Text = T.TitleTeam .. " " .. roster.Owned .. "/" .. roster.Cap
		if view == "Team" then
			renderTeam(state)
		else
			renderJournal(state, roster)
		end
		if pickerFor and picker.isOpen() then
			renderPicker(state)
		end
	end

	-- Snapshots come with every cure; the panel only redraws while it's open (and once as it opens).
	ctx.onState(function(state: Types.Snapshot)
		if modal.isOpen() and not busy then
			render(state)
		end
	end)

	-- The 🎲 chips follow Night Rush and Golden Hour.
	local function oddsChanged()
		if modal.isOpen() and view ~= "Team" then
			render(ctx.State)
		end
	end
	Workspace:GetAttributeChangedSignal("GoldenHour"):Connect(oddsChanged)
	Workspace:GetAttributeChangedSignal("NightRush"):Connect(oddsChanged)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(oddsChanged)

	-- 🏷️ on your cards: the Market's listings as everyone sees them.
	ctx.on("MarketNews", function(marketView: any)
		listed = Pure.listedSet(marketView, player.UserId)
		marketAsked = true
		if modal.isOpen() and view == "Team" then
			render(ctx.State)
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- NEW! stamps: a little card above the 👩‍⚕️ button that flies into it
	--------------------------------------------------------------------------------------------------------------
	local stampGui: ScreenGui? = nil
	local stampQueue: { Stamp } = {}
	local stamping = false

	local function showStamp(item: Stamp)
		local nurse = rawget(data.Nurses, item.NurseId)
		if not nurse then
			return
		end
		local gui = stampGui or Kit.screen("NurseStamps", Theme.DisplayOrder.Fx)
		stampGui = gui
		local info = rarityInfo(nurse.Rarity)
		local color = hexColor(info.Color, Theme.Colors.Quiet)
		local target = Hud.target("Nurses")
		local shown = target ~= nil and target.Visible and target.AbsoluteSize.X > 0
		local origin = gui.AbsolutePosition
		local area = gui.AbsoluteSize

		local card = frame({
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.fromOffset(STAMP_SIZE.X, STAMP_SIZE.Y),
			Visible = false,
			ZIndex = 1,
			Parent = gui,
		})
		if shown and target then
			local centre = target.AbsolutePosition + target.AbsoluteSize / 2 - origin
			local x = math.clamp(
				centre.X,
				STAMP_SIZE.X / 2 + 8,
				math.max(STAMP_SIZE.X / 2 + 8, area.X - STAMP_SIZE.X / 2 - 8)
			)
			card.Position = UDim2.fromOffset(x, target.AbsolutePosition.Y - origin.Y - 12)
		else
			card.Position = UDim2.new(1, -(STAMP_SIZE.X / 2 + 16), 1, -120)
		end
		Kit.corner(card, 18)
		Kit.rarityFrame(card, nurse.Rarity)
		local stopRays = Kit.celebrate(card, color)
		local face = frame({
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(1, -20, 0, 96),
			BackgroundColor3 = Kit.lighten(color, 0.45),
			ZIndex = 1,
			Parent = card,
		})
		Kit.corner(face, 12)
		Palette.candyGradient(face)
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		addCap(portrait, color)
		local name = Kit.label({
			Name = "NurseName",
			Text = nurse.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -14, 0, 30),
			ZIndex = 1,
			Parent = card,
		})
		textLimit(name, 22)
		local ribbon = Kit.label({
			Name = "New",
			Text = if item.Kind == "Level" then T.LevelUp .. " Lv " .. tostring(item.Level or 2) else T.New,
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = if item.Kind == "Level" then Theme.Colors.Good else Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(-10, -12),
			Size = UDim2.fromOffset(78, 28),
			Rotation = -10,
			ZIndex = 3,
			Parent = card,
		})
		Kit.corner(ribbon, 14)
		Kit.stroke(ribbon, Theme.Colors.Outline, 2.5)
		padButton(ribbon, 6, 3)

		Kit.popIn(card)
		if item.Kind == "Seen" then
			Hud.sound("Sparkle") -- a queued stamp gets its own; the first one shares the NurseNews sparkle
		end
		task.wait(STAMP_SECONDS)

		local function finish()
			stopRays()
			card:Destroy()
		end
		if Kit.reducedMotion() or not shown or not target then
			Kit.popOut(card, finish)
			task.wait(0.2)
			return
		end
		local centre = target.AbsolutePosition + target.AbsoluteSize / 2 - origin
		local scale = card:FindFirstChild("KitScale")
		local flyInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fly = TweenService:Create(card, flyInfo, { Position = UDim2.fromOffset(centre.X, centre.Y + 16) })
		if scale and scale:IsA("UIScale") then
			TweenService:Create(scale, flyInfo, { Scale = 0.15 }):Play()
		end
		fly:Play()
		fly.Completed:Wait()
		finish()
		Hud.pop(target, 1.2)
	end

	local function stamp(nurseId: string, kind: string, level: number?)
		if not TutorialLogic.isDone(ctx.State.Tutorial) or modal.isOpen() then
			return
		end
		if #stampQueue >= STAMP_QUEUE_MAX then
			return
		end
		table.insert(stampQueue, { NurseId = nurseId, Kind = kind, Level = level })
		if stamping then
			return
		end
		stamping = true
		task.spawn(function()
			while #stampQueue > 0 do
				local item = table.remove(stampQueue, 1) :: Stamp
				if not modal.isOpen() then
					local ok, err = pcall(showStamp, item)
					if not ok then
						warn("[NursePanel] stamp failed: " .. tostring(err))
					end
				end
			end
			stamping = false
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- News, opening and closing
	--------------------------------------------------------------------------------------------------------------
	ctx.on("NurseNews", function(info: any)
		if type(info) ~= "table" or type(info.NurseId) ~= "string" or not rawget(data.Nurses, info.NurseId) then
			return
		end
		local kind = info.Kind
		if kind == "Listed" then
			listed[info.NurseId] = if info.On == true then true else nil
		elseif kind == "Sold" or kind == "Gone" then
			listed[info.NurseId] = nil
		end
		if Pure.noteNews(fresh, info) then
			ctx.fire("NursesNew", Pure.count(fresh))
		end
		if kind == "Seen" then
			stamp(info.NurseId, "Seen", nil)
		elseif (kind == "Level" and info.Ability ~= true) or (kind == "Hired" and info.New ~= true) then
			-- (a level that made its ability stronger, Lv 5 / 10, gets UI/Celebrate's NurseLevel screen instead)
			stamp(info.NurseId, "Level", if type(info.Level) == "number" then info.Level else nil)
		end
		if modal.isOpen() then
			render(ctx.State)
			if kind == "Seen" or kind == "Hired" or kind == "Level" then
				local teamCard = teamCards[info.NurseId]
				local journalCard = cardsById[info.NurseId]
				if view == "Team" and teamCard then
					Hud.pop(teamCard.Frame, 1.15)
				elseif view ~= "Team" and journalCard then
					Hud.pop(journalCard.Frame, 1.15)
				end
			end
		end
	end)

	ctx.on("Open", function(name: any, tab: any)
		if name ~= "Nurses" then
			return
		end
		local target = Pure.openView(tab, fresh, data.Nurses, rarityOrder, if view ~= "" then view else nil)
		showView(target)
		modal.open()
		render(ctx.State)
		if view == "Team" then
			startRings()
		end
		-- NEW! moment: the cards with news pop as the panel opens.
		local popped = false
		if view == "Team" then
			for nurseId, card in teamCards do
				if fresh[nurseId] == "Level" or fresh[nurseId] == "Hired" then
					Hud.pop(card.Frame, 1.1)
					popped = true
				end
			end
		elseif pages[view] then
			for _, card in pages[view].Cards do
				if fresh[card.Id] == "Seen" or fresh[card.Id] == "Hired" then
					Hud.pop(card.Frame, 1.15)
					popped = true
				end
			end
		end
		if popped then
			Hud.sound("Sparkle")
		end
	end)

	-- Closing the panel counts its news as seen (the NEW! stickers go on the next open's redraw), stops the rings and
	-- closes the job picker.
	ctx.on("ModalClosed", function(name: any)
		if name ~= "Nurses" then
			return
		end
		ringToken += 1
		if picker.isOpen() then
			picker.close()
		end
		if next(fresh) ~= nil then
			table.clear(fresh)
			ctx.fire("NursesNew", 0)
		end
	end)

	showView(rarityOrder[1])
end

return NursePanel
