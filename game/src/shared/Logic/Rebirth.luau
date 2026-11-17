--!strict
-- Rebirths: "🏢 Open a new branch" (Progression v2 build plan §B1/§B5/§B7; design §7/§8, memory-20261116-017/-019).
-- Optional, never pushed (red line 3): no dots, no repeat toasts, and the keep/reset screen comes first. Pure: no
-- Roblox services, no requires. `cfg` is Shared/Config (cfg.Rebirth); `perks` Shared/Data/Perks, `themes`
-- Shared/Data/Themes, `tree` Shared/Data/Tree (or its .Nodes), `content` = { Perks, Themes, Nurses, Decor } (the
-- Shared/Data modules). Data maps are read with rawget, so "Order" is never an id.
--
--   Rebirth.cost(count, cfg): number         the NEXT rebirth's cost after `count` done: cfg.Rebirth.Cost[count + 1];
--                                            past the table x Growth a rebirth, rounded to 2 significant figures
--   Rebirth.canRebirth(data, cfg): (ok, message)   hospital Lv >= MinLevel ("Needs 🏥 Lv 5": UI/Icons.needs's
--                                            words), cash >= cost ("Need 💰50,000"); "" when ok. (The server
--                                            also checks the tutorial, saving, an open treat session and its
--                                            cooldown: §B3 OpenBranch)
--   Rebirth.multiplier(count, cfg, kind?): number   1 + CashPerRebirth (StarsPerRebirth for kind "Stars") x
--                                            min(count, MaxBonusRebirths): added, not compounded (§E12: R4 x2, R20 x6)
--   Rebirth.apply(data, cfg, offer, content): ApplyResult
--       MUTATES `data` (call it inside ONE PlayerData.update, with no yield):
--         · Rebirth.Count + 1, Rebirth.Points + PointsPerRebirth, Rebirth.Offer = offer (cleaned: unique, not owned)
--         · Cash -> StartCash (SeedMoney: its Value) · every upgrade -> 0 (WarmUp: Faster Hands 2, Tip Jar 1) ·
--           Level -> 1 (ClinicStart: its Value) · Rooms -> { Stand } (+ BathRoom with BathReady)
--         · Decor.Placed keeps only slots in rooms still owned (the rest goes back to your decor, still owned);
--           Stats.RoomsBefore += the rooms reset (the 🏠 Builder badge never loses them)
--         · Theme -> the newest theme unlocked; Pending += the rebirth-only nurse of this count (FounderFennec at R5)
--           unless owned or already waiting (at most 4); Decor.Owned += the Branch Trophy of this count (R6-R10: it
--           only ever adds)
--         · never touches Book, Story, Nurses, NurseIndex, JournalSets, Stars, Cured, Badges, Stats (but
--           RoomsBefore), Playtime, Boosts, Daily, Mailbox, Hearts*, WeekCures, Tutorial, Simple, Rebirth.Perks,
--           Rebirth.Tree, Rebirth.Told or anything else in Decor.Owned
--       Returns { Count, Theme, Unlocks (Rebirth.unlocks(Count)), Pending (nurses added), Trophies (decor added),
--       RoomsReset }
--   Rebirth.startCash(data, cfg, perks): number   the cash a new branch starts with: Seed Money's Value when owned,
--                                            else cfg.Rebirth.StartCash. A rebirth sets ALL cash to this (it isn't
--                                            the cost taken off), and the keep/reset screen shows it
--   Rebirth.offer(owned, pool, r01s, size?): { PerkId }
--       up to `size` (default 3; at most #r01s) distinct cards not in `owned`, each pick even among those left (r01s
--       in [0, 1)); { "TreePoints" } (the Fallback) when none are left. `pool` is Data/Perks
--   Rebirth.liveOffer(offer, perks): { PerkId }
--       the waiting cards that can be chosen: known ones (Data/Perks or the Fallback), in order. A waiting offer with
--       no known card left (a card renamed or removed since) is { "TreePoints" }, so a branch can always open again
--   Rebirth.choose(data, perkId, perks, cfg?): (ok, message)
--       MUTATES: perkId must be in liveOffer(Rebirth.Offer) and not in Rebirth.Perks ("Oops! Try again."). It's added to Perks
--       (the Fallback "TreePoints" adds its Value to Points instead), Offer clears, and a start-of-branch card applies
--       now (you choose at the start of a branch): BathReady owns the BathRoom, SeedMoney adds its Value -
--       StartCash, WarmUp raises Faster Hands to 2 and Tip Jar to 1, ClinicStart raises Level to its Value
--   Rebirth.UNLOCKS[id] = { Icon, Text, Rebirths }   what each rebirth opens (display rows; Text <= 4 words). The ids
--                                            are kept; Pharmacy2 is 💊 Expert Dispensing since the Real Clinic: the
--                                            dispensary's dose band (Config.MiniGame.Games.Dose) is
--                                            Config.Dispensary.ExpertBand (x1.5) wider for that player
--                                            (the server checks Rebirth.has(count, "Pharmacy2"))
--   Rebirth.unlocks(count): { string }       the unlock ids NEW at exactly this count: R1 MythicSecret, SunnyWing ·
--                                            R2 Helicopter, Pharmacy2 · R3 Golden, LevelCap15 · R4 NightClinic · R5
--                                            FounderFennec, Mascot · R6-R10 Trophy<count> (Trophy6..Trophy10)
--   Rebirth.has(count, unlockId): boolean    unlocked at or before `count`
--   Rebirth.themes(count, themes): { ThemeId }   unlocked themes (Rebirths <= count), in Order
--   Rebirth.theme(data, themes): ThemeId     the theme shown: the save's Rebirth.Theme when it's known and
--                                            unlocked, else Candy
--   Rebirth.effects(data, cfg, perks, tree): Effects   the flat merge of the owned perks and the tree (§B7):
--       Patience, Tips, MakeSpeed, Cash, Stars (percent; Server/Boosts caps them with Config.BranchCaps) · Ease
--       (1..1.3, Perfect windows) · Walk (studs a second added) · Lift (ride seconds x this, >= 0.2) · Bargain
--       (fraction off belt and Agency prices) · Arrive (spawn seconds x this) · XP (nurse XP x this) · NightOwl,
--       BeltScout, TwinCounters, LuckyStock (booleans) · Tray (+carry) · SirenPro (A&E interval / this) · Recharge
--       (ability cooldowns x this) · DoubleShift (nurse seconds / this)
--   Rebirth.KEEP · RESET · GET               the keep/reset screen's rows ({ Icon, Text }, Text <= 3 words). GET is
--                                            what every rebirth gives; the Branch panel drops "+1 nurse slot" once the
--                                            roster is at its Max and adds the next unlocks and theme by name
--   Rebirth.WARM_UP                          the WarmUp card's upgrades { Speed = 2, Tips = 1 }

export type Row = { Icon: string, Text: string }
export type Effects = {
	Patience: number,
	Tips: number,
	Ease: number,
	MakeSpeed: number,
	Walk: number,
	Lift: number,
	Cash: number,
	Stars: number,
	Bargain: number,
	Arrive: number,
	XP: number,
	NightOwl: boolean,
	Tray: number,
	BeltScout: boolean,
	SirenPro: number,
	Recharge: number,
	TwinCounters: boolean,
	DoubleShift: number,
	LuckyStock: boolean,
}
export type ApplyResult = {
	Count: number,
	Theme: string,
	Unlocks: { string },
	Pending: { string },
	Trophies: { string },
	RoomsReset: number,
}

local Rebirth = {}

Rebirth.FALLBACK = "TreePoints" -- Data/Perks.FallbackId
Rebirth.MAX_COUNT = 1000 -- Logic/Schema.MAX_REBIRTHS
Rebirth.MAX_POINTS = 1000 -- Logic/Schema.MAX_POINTS
Rebirth.MAX_PENDING = 4 -- Logic/Schema.MAX_PENDING
Rebirth.MAX_OFFER = 3
Rebirth.WARM_UP = table.freeze({ Speed = 2, Tips = 1 })
Rebirth.START_ROOM = "BathRoom"
Rebirth.DEFAULT_THEME = "Candy"

local OOPS = "Oops! Try again."

Rebirth.KEEP = table.freeze({
	table.freeze({ Icon = "📖", Text = "Patient Book" }),
	table.freeze({ Icon = "👩‍⚕️", Text = "Your nurses" }),
	table.freeze({ Icon = "📖", Text = "Nurse Journal" }),
	table.freeze({ Icon = "⭐", Text = "Your stars" }),
	table.freeze({ Icon = "🏅", Text = "Badges and rank" }),
	table.freeze({ Icon = "🌸", Text = "Your decor" }),
	table.freeze({ Icon = "🃏", Text = "Perks and tree" }),
}) :: { Row }

Rebirth.RESET = table.freeze({
	table.freeze({ Icon = "💰", Text = "Cash" }),
	table.freeze({ Icon = "⚡", Text = "Upgrades" }),
	table.freeze({ Icon = "🏥", Text = "Hospital level" }),
	table.freeze({ Icon = "🏠", Text = "Rooms" }),
}) :: { Row }

Rebirth.GET = table.freeze({
	table.freeze({ Icon = "💰", Text = "+25% cash" }),
	table.freeze({ Icon = "⭐", Text = "+25% stars" }),
	table.freeze({ Icon = "🌳", Text = "+3 tree points" }),
	table.freeze({ Icon = "🃏", Text = "A perk card" }),
	table.freeze({ Icon = "👩‍⚕️", Text = "+1 nurse slot" }),
	table.freeze({ Icon = "🎨", Text = "A new look" }),
}) :: { Row }

local function unlock(icon: string, text: string, rebirths: number): any
	return table.freeze({ Icon = icon, Text = text, Rebirths = rebirths })
end

Rebirth.UNLOCKS = table.freeze({
	MythicSecret = unlock("🐉", "Mythic and Secret nurses", 1),
	SunnyWing = unlock("🌻", "Sunny wing patients", 1),
	Helicopter = unlock("🚁", "Air ambulance", 2),
	Pharmacy2 = unlock("💊", "Expert Dispensing", 2), -- the id from Progression v2 (the Pharmacy's tier 2), kept
	Golden = unlock("🌟", "Golden patients", 3), -- the UI adds the odds (Config.GoldenChance)
	LevelCap15 = unlock("⬆️", "Nurses to Lv 15", 3),
	NightClinic = unlock("🌙", "Night Clinic upgrade", 4),
	FounderFennec = unlock("🐾", "A special nurse", 5),
	Mascot = unlock("🎈", "A clinic mascot", 5),
	Trophy6 = unlock("🏆", "Branch trophy", 6),
	Trophy7 = unlock("🏆", "Branch trophy", 7),
	Trophy8 = unlock("🏆", "Branch trophy", 8),
	Trophy9 = unlock("🏆", "Branch trophy", 9),
	Trophy10 = unlock("🏆", "Branch trophy", 10),
}) :: { [string]: { Icon: string, Text: string, Rebirths: number } }

local BY_COUNT: { [number]: { string } } = {
	[1] = { "MythicSecret", "SunnyWing" },
	[2] = { "Helicopter", "Pharmacy2" },
	[3] = { "Golden", "LevelCap15" },
	[4] = { "NightClinic" },
	[5] = { "FounderFennec", "Mascot" },
	[6] = { "Trophy6" },
	[7] = { "Trophy7" },
	[8] = { "Trophy8" },
	[9] = { "Trophy9" },
	[10] = { "Trophy10" },
}

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function whole(value: any): number
	return math.max(0, math.floor(num(value, 0)))
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
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

local function countOf(data: any): number
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	return if type(rebirth) == "table" then whole(rebirth.Count) else 0
end

-- 50000 -> "50,000"
local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- Rounded to 2 significant figures (2,850,000 -> 2,900,000).
local function twoFigures(x: number): number
	if x < 100 then
		return math.floor(x + 0.5)
	end
	local step = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

function Rebirth.cost(count: number, cfg: any): number
	local s = settings(cfg)
	local table_ = if type(s.Cost) == "table" then s.Cost else {}
	local n = whole(count)
	local listed = table_[n + 1]
	if type(listed) == "number" then
		return listed
	end
	local last = num(table_[#table_], 50000)
	local growth = math.max(1, num(s.Growth, 1.5))
	local cost = last
	for _ = #table_ + 1, math.min(n + 1, #table_ + 200) do
		cost = twoFigures(cost * growth)
	end
	return cost
end

function Rebirth.canRebirth(data: any, cfg: any): (boolean, string)
	if type(data) ~= "table" then
		return false, OOPS
	end
	local minLevel = math.max(1, math.floor(num(settings(cfg).MinLevel, 5)))
	if num(data.Level, 1) < minLevel then
		return false, "Needs 🏥 Lv " .. minLevel
	end
	local cost = Rebirth.cost(countOf(data), cfg)
	if num(data.Cash, 0) < cost then
		return false, "Need 💰" .. commas(cost)
	end
	return true, ""
end

function Rebirth.multiplier(count: number, cfg: any, kind: string?): number
	local s = settings(cfg)
	local per = num(if kind == "Stars" then s.StarsPerRebirth else s.CashPerRebirth, 0.25)
	local counted = math.min(whole(count), whole(s.MaxBonusRebirths))
	return 1 + math.max(0, per) * counted
end

function Rebirth.unlocks(count: number): { string }
	local list = BY_COUNT[whole(count)]
	return if list then table.clone(list) else {}
end

function Rebirth.has(count: number, unlockId: string): boolean
	local info = Rebirth.UNLOCKS[unlockId]
	return info ~= nil and whole(count) >= info.Rebirths
end

function Rebirth.themes(count: number, themes: any): { string }
	local out: { string } = {}
	for _, id in ordered(themes) do
		if num(row(themes, id).Rebirths, 0) <= whole(count) then
			table.insert(out, id)
		end
	end
	return out
end

function Rebirth.theme(data: any, themes: any): string
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	local chosen = if type(rebirth) == "table" then rebirth.Theme else nil
	local themeRow = row(themes, chosen)
	if themeRow and num(themeRow.Rebirths, 0) <= countOf(data) then
		return chosen :: string
	end
	return Rebirth.DEFAULT_THEME
end

-- The owned perks' start-of-branch effects.
type Start = { Cash: number?, Upgrades: boolean, Level: number?, Room: boolean }
local function startOf(perkIds: { string }, perks: any): Start
	local start: Start = { Cash = nil, Upgrades = false, Level = nil, Room = false }
	for _, perkId in perkIds do
		local perk = row(perks, perkId)
		if perk then
			if perk.Kind == "StartCash" then
				start.Cash = math.max(start.Cash or 0, whole(perk.Value))
			elseif perk.Kind == "StartUpgrades" then
				start.Upgrades = true
			elseif perk.Kind == "StartLevel" then
				start.Level = math.max(start.Level or 1, math.max(1, whole(perk.Value)))
			elseif perk.Kind == "StartRoom" then
				start.Room = true
			end
		end
	end
	return start
end

local function cleanOffer(offer: any, owned: { string }): { string }
	local out: { string } = {}
	if type(offer) ~= "table" then
		return out
	end
	for _, perkId in ipairs(offer) do
		if #out >= Rebirth.MAX_OFFER then
			break
		end
		if type(perkId) == "string" and not table.find(out, perkId) and not table.find(owned, perkId) then
			table.insert(out, perkId)
		end
	end
	return out
end

function Rebirth.startCash(data: any, cfg: any, perks: any): number
	local rebirth = if type(data) == "table" and type(data.Rebirth) == "table" then data.Rebirth else {}
	local owned = if type(rebirth.Perks) == "table" then rebirth.Perks else {}
	return startOf(owned, perks).Cash or whole(settings(cfg).StartCash)
end

function Rebirth.apply(data: any, cfg: any, offer: { string }, content: any): ApplyResult
	local s = settings(cfg)
	local c = if type(content) == "table" then content else {}
	local rebirth = data.Rebirth
	local count = math.min(Rebirth.MAX_COUNT, whole(rebirth.Count) + 1)
	rebirth.Count = count
	rebirth.Points = math.min(Rebirth.MAX_POINTS, whole(rebirth.Points) + whole(s.PointsPerRebirth))
	rebirth.Offer = cleanOffer(offer, rebirth.Perks)

	local start = startOf(rebirth.Perks, c.Perks)
	data.Cash = start.Cash or whole(s.StartCash)
	for upgradeId in data.Upgrades do
		data.Upgrades[upgradeId] = 0
	end
	if start.Upgrades then
		for upgradeId, level in Rebirth.WARM_UP do
			data.Upgrades[upgradeId] = level
		end
	end
	data.Level = start.Level or 1

	local reset = 0
	local rooms: { [string]: boolean } = { Stand = true }
	if start.Room then
		rooms[Rebirth.START_ROOM] = true
	end
	for roomId, owned in data.Rooms do
		if owned == true and not rooms[roomId] then
			reset += 1
		end
	end
	data.Rooms = rooms
	for slotKey in table.clone(data.Decor.Placed) do
		local roomId = if type(slotKey) == "string" then string.match(slotKey, "^(%w+):") else nil
		if not (roomId and rooms[roomId]) then
			data.Decor.Placed[slotKey] = nil
		end
	end
	data.Stats.RoomsBefore = whole(data.Stats.RoomsBefore) + reset

	local unlocked = Rebirth.themes(count, c.Themes)
	rebirth.Theme = unlocked[#unlocked] or ""

	local pending: { string } = {}
	for _, nurseId in ordered(c.Nurses) do
		local nurse = row(c.Nurses, nurseId)
		if
			nurse.Source ~= nil
			and whole(nurse.Rebirths) == count
			and data.Nurses[nurseId] == nil
			and not table.find(rebirth.Pending, nurseId)
			and #rebirth.Pending < Rebirth.MAX_PENDING
		then
			table.insert(rebirth.Pending, nurseId)
			table.insert(pending, nurseId)
		end
	end

	local trophies: { string } = {}
	for _, decorId in ordered(c.Decor) do
		local decor = row(c.Decor, decorId)
		if decor.EarnedBy == "Rebirth" and whole(decor.Rebirths) == count and data.Decor.Owned[decorId] ~= true then
			data.Decor.Owned[decorId] = true
			table.insert(trophies, decorId)
		end
	end

	return {
		Count = count,
		Theme = rebirth.Theme,
		Unlocks = Rebirth.unlocks(count),
		Pending = pending,
		Trophies = trophies,
		RoomsReset = reset,
	}
end

function Rebirth.offer(owned: { string }, pool: any, r01s: { number }, size: number?): { string }
	local left: { string } = {}
	for _, perkId in ordered(pool) do
		if not (type(owned) == "table" and table.find(owned, perkId)) then
			table.insert(left, perkId)
		end
	end
	if #left == 0 then
		return { Rebirth.FALLBACK }
	end
	local want = math.min(whole(size or Rebirth.MAX_OFFER), Rebirth.MAX_OFFER, #r01s)
	local out: { string } = {}
	for index = 1, want do
		if #left == 0 then
			break
		end
		local r = math.clamp(num(r01s[index], 0), 0, 0.999999999)
		local pick = math.floor(r * #left) + 1
		table.insert(out, table.remove(left, pick) :: string)
	end
	return out
end

function Rebirth.liveOffer(offer: any, perks: any): { string }
	local out: { string } = {}
	if type(offer) ~= "table" then
		return out
	end
	local waiting = false
	for _, perkId in ipairs(offer) do
		if type(perkId) == "string" then
			waiting = true
			local known = perkId == Rebirth.FALLBACK or row(perks, perkId) ~= nil
			if known and not table.find(out, perkId) then
				table.insert(out, perkId)
			end
		end
	end
	if waiting and #out == 0 then
		return { Rebirth.FALLBACK }
	end
	return out
end

function Rebirth.choose(data: any, perkId: string, perks: any, cfg: any?): (boolean, string)
	if type(data) ~= "table" or type(data.Rebirth) ~= "table" or type(perkId) ~= "string" then
		return false, OOPS
	end
	local rebirth = data.Rebirth
	local offer = Rebirth.liveOffer(rebirth.Offer, perks)
	if not table.find(offer, perkId) or table.find(rebirth.Perks, perkId) then
		return false, OOPS
	end
	if perkId == Rebirth.FALLBACK then
		local fallback = if type(perks) == "table" then perks.Fallback else nil
		local value = if type(fallback) == "table" then whole(fallback.Value) else 2
		rebirth.Points = math.min(Rebirth.MAX_POINTS, whole(rebirth.Points) + value)
		rebirth.Offer = {}
		return true, ""
	end
	local perk = row(perks, perkId)
	if not perk then
		return false, OOPS
	end
	table.insert(rebirth.Perks, perkId)
	rebirth.Offer = {}
	-- A start-of-branch card applies now: you choose at the start of a branch.
	if perk.Kind == "StartRoom" then
		data.Rooms[Rebirth.START_ROOM] = true
	elseif perk.Kind == "StartCash" then
		data.Cash = whole(data.Cash) + math.max(0, whole(perk.Value) - whole(settings(cfg).StartCash))
	elseif perk.Kind == "StartUpgrades" then
		for upgradeId, level in Rebirth.WARM_UP do
			data.Upgrades[upgradeId] = math.max(whole(data.Upgrades[upgradeId]), level)
		end
	elseif perk.Kind == "StartLevel" then
		data.Level = math.max(whole(data.Level), whole(perk.Value))
	end
	return true, ""
end

-- Tree ranks x Value per Effect key (the same sums as Logic/Tree.effects; Rebirth.spec checks they agree).
local function treeEffects(tree: any, nodes: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(tree) ~= "table" then
		return out
	end
	for nodeId, rawRank in tree do
		local def = row(nodes, nodeId)
		local rank = if def then math.min(whole(rawRank), math.max(1, whole(def.Max))) else 0
		if def and rank > 0 and type(def.Effect) == "string" then
			local value = num(def.Value, 0)
			if def.Effect == "DoubleShift" then
				out.DoubleShift = value
			elseif def.Effect == "TwinCounters" or def.Effect == "LuckyStock" then
				out[def.Effect] = 1
			else
				out[def.Effect] = (out[def.Effect] or 0) + value * rank
			end
		end
	end
	return out
end

function Rebirth.effects(data: any, _cfg: any, perks: any, tree: any): Effects
	local rebirth = if type(data) == "table" and type(data.Rebirth) == "table" then data.Rebirth else {}
	local nodes = if type(tree) == "table" and type(tree.Nodes) == "table" then tree.Nodes else tree
	local t = treeEffects(rebirth.Tree, nodes)
	local out: Effects = {
		Patience = t.Patience or 0,
		Tips = t.Tips or 0,
		Ease = 1 + (t.Ease or 0),
		MakeSpeed = t.MakeSpeed or 0,
		Walk = t.Walk or 0,
		Lift = math.max(0.2, 1 - (t.Lift or 0)),
		Cash = t.Cash or 0,
		Stars = t.Stars or 0,
		Bargain = math.clamp(t.Bargain or 0, 0, 0.5),
		Arrive = 1,
		XP = 1,
		NightOwl = false,
		Tray = 0,
		BeltScout = false,
		SirenPro = 1,
		Recharge = 1,
		TwinCounters = (t.TwinCounters or 0) > 0,
		DoubleShift = math.max(1, t.DoubleShift or 1),
		LuckyStock = (t.LuckyStock or 0) > 0,
	}
	local owned = if type(rebirth.Perks) == "table" then rebirth.Perks else {}
	for _, perkId in owned do
		local perk = row(perks, perkId)
		if perk then
			local value = num(perk.Value, 0)
			if perk.Kind == "Arrive" and value > 0 then
				out.Arrive *= value
			elseif perk.Kind == "XP" and value > 0 then
				out.XP *= value
			elseif perk.Kind == "NightOwl" then
				out.NightOwl = true
			elseif perk.Kind == "Tray" then
				out.Tray += math.max(0, math.floor(value))
			elseif perk.Kind == "BeltScout" then
				out.BeltScout = true
			elseif perk.Kind == "SirenPro" and value > 0 then
				out.SirenPro *= value
			elseif perk.Kind == "Patience" then
				out.Patience += math.max(0, value)
			elseif perk.Kind == "Recharge" and value > 0 then
				out.Recharge *= value
			end
		end
	end
	return out
end

return Rebirth
