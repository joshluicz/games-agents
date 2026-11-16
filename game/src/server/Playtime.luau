--!strict
-- Time-played rewards: the daily play gifts and the Doctor ranks (game/README.md "Play gifts, Doctor ranks, boosts
-- and badges"). Server only; the rules are Logic/Playtime (Lune-tested), the content Data/Playtime.
--
--   Playtime.pending(p): number       active seconds counted since the last save (Server/Boosts reads it)
--   Playtime.commit(p): boolean       saves them now: today's and the total, timed boosts tick, new ranks pay
--   Playtime.addToday(p, s) · Playtime.addTotal(p, s)   the 🛠️ Admin panel only: +s seconds today / all time
--   Playtime.rankOf(p): number        the Doctor rank rewarded (0 = Trainee)
--   start(): the counting loop, the ClaimPlayGift remote, the clinic sign's rank badge
--
-- What counts. Once a second, for every player whose save has loaded and who has a clinic (Plots.getPlot): the time
-- counts while they're ACTIVE, i.e. they moved at least MOVE_STUDS or acted (any served remote, any ProximityPrompt)
-- in the last Config.PlaytimeIdleSeconds. Standing still or away from the keyboard pauses it, so play time can't be
-- farmed past normal play. Timed boosts (Data.Boosts) tick with the same seconds.
-- Saving. Counted seconds wait in memory (`Pending`) and are written with PlayerData.update when a minute has
-- gathered, or sooner when a gift unlocks, a rank is reached or a timed boost runs out, so the Snapshot (and the
-- HUD dot) are on time without a save every second. On leave the rest is written (PlayerRemoving runs before
-- PlayerData's leave-save). The live values are the player attributes PlayToday and PlayTotal (whole seconds,
-- rolled over to today) and PlayCounting (true while the time counts), so the HUD ring moves every second.
-- The day. A gift belongs to the UTC day (Daily.today(), which follows the Studio forward-UtcDay switch): when the day
-- changes, everyone's gifts refill at once (no rejoin), and TodaySeconds starts again. Nothing carries over and
-- nothing is lost: no streaks.
-- Ranks. When TotalSeconds passes a rank's Hours: its exclusive decor is owned (one update with the rank), a toast,
-- the Roblox badge (Server/Badges.awardRoblox, Config.Badges[rank.Id]), and the clinic sign's RankBadge label. On
-- join, the Roblox badges for every rank already reached are checked again (a badge made after they got there).
--
-- Remote (Remotes.serve: rate limit + pcall). Every argument is untrusted:
--   ClaimPlayGift(index)   a whole number 1..#Gifts whose gift today's active play unlocked and that isn't opened yet
--                          -> its Cash (Economy.addCash), Stars (Progress.addStars) and timed boost (Boosts.addTimed)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PlaytimeData = require(Shared.Data.Playtime)
local BoostData = require(Shared.Data.Boosts)
local Decor = require(Shared.Data.Decor)
local PlaytimeLogic = require(Shared.Logic.Playtime)
local BoostsLogic = require(Shared.Logic.Boosts)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Daily = require(script.Parent.Daily)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)
local Boosts = require(script.Parent.Boosts)
local Badges = require(script.Parent.Badges)

local Playtime = {}

local TICK = 1
local MAX_STEP = 5 -- a long server hitch never counts as more than this
local COMMIT_SECONDS = 60
local MOVE_STUDS = 1
local RANK_LABEL = "RankBadge" -- a TextLabel in the plot's Sign.SignGui (PlotBuilder makes one; added if missing)

local GIFTS = PlaytimeData.Gifts :: { PlaytimeLogic.Gift }
local RANKS = PlaytimeData.Ranks :: { PlaytimeLogic.Rank }

type Session = {
	Pending: number, -- active seconds not saved yet
	LastTick: number,
	LastActive: number,
	LastPos: Vector3?,
	NextEvent: number, -- save once Pending reaches this (a gift, a rank or a boost's end; at most COMMIT_SECONDS)
	Counting: boolean,
}

local sessions: { [Player]: Session } = {}

local function present(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function today(): number
	return Daily.today()
end

------------------------------------------------------------------------------------------------------------------
-- The clinic sign's rank badge
------------------------------------------------------------------------------------------------------------------

local function rankLabel(plot: Types.Plot?): TextLabel?
	local sign = plot and plot.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	if not gui then
		return nil
	end
	local found = gui:FindFirstChild(RANK_LABEL)
	if found then
		return if found:IsA("TextLabel") then found else nil
	end
	-- A kit sign without one: a small white badge in the bottom right corner.
	local label = Instance.new("TextLabel")
	label.Name = RANK_LABEL
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.fromScale(0.95, 0.93)
	label.Size = UDim2.fromScale(0.4, 0.27)
	label.BackgroundColor3 = Palette.White
	label.BackgroundTransparency = 0.05
	label.Font = Palette.DisplayFont
	label.TextColor3 = Palette.Ink
	label.TextScaled = true
	label.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Palette.Outline
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return label
end

local function showRank(player: Player)
	local data = PlayerData.get(player)
	local label = rankLabel(Plots.getPlot(player))
	if not data or not label then
		return
	end
	local rank = RANKS[data.Playtime.Rank]
	local shown = rank or PlaytimeData.Trainee
	label.Text = shown.Icon .. " " .. shown.Name
	label.Visible = true
end

------------------------------------------------------------------------------------------------------------------
-- Counting
------------------------------------------------------------------------------------------------------------------

function Playtime.pending(player: Player): number
	local session = sessions[player]
	return if session then math.floor(session.Pending) else 0
end

function Playtime.rankOf(player: Player): number
	local data = PlayerData.get(player)
	return if data then data.Playtime.Rank else 0
end

-- The seconds until something should show up in the Snapshot: a gift unlocking, a rank, a timed boost ending.
local function nextEvent(data: Types.Data, day: number): number
	local soonest = COMMIT_SECONDS
	local _, giftLeft = PlaytimeLogic.nextGift(data.Playtime, day, GIFTS)
	local _, rankLeft = PlaytimeLogic.nextRank(data.Playtime.TotalSeconds, RANKS)
	local boostLeft = BoostsLogic.soonest(data.Boosts) or 0
	for _, left in { giftLeft, rankLeft, boostLeft } do
		if left > 0 then
			soonest = math.min(soonest, math.ceil(left))
		end
	end
	return math.max(1, soonest)
end

local function publish(player: Player, session: Session, data: Types.Data)
	local live = PlaytimeLogic.add(data.Playtime, today(), math.floor(session.Pending))
	local todaySeconds, total = math.floor(live.TodaySeconds), math.floor(live.TotalSeconds)
	if player:GetAttribute("PlayToday") ~= todaySeconds then
		player:SetAttribute("PlayToday", todaySeconds)
	end
	if player:GetAttribute("PlayTotal") ~= total then
		player:SetAttribute("PlayTotal", total)
	end
end

local function rankedUp(player: Player, ranks: { number })
	local last = RANKS[ranks[#ranks]]
	if not last then
		return
	end
	local decor = rawget(Decor :: any, last.Decor)
	Remotes.news(player, last.Icon .. " " .. last.Name .. "! New decor " .. (if decor then decor.Icon else "🎁"))
	for _, index in ranks do
		Badges.awardRoblox(player, RANKS[index].Id)
	end
	showRank(player)
end

function Playtime.commit(player: Player): boolean
	local session = sessions[player]
	local data = PlayerData.get(player)
	if not session or not data then
		return false
	end
	local day = today()
	local whole = math.floor(session.Pending)
	local readyBefore = #PlaytimeLogic.ready(data.Playtime, day, GIFTS)
	local after = PlaytimeLogic.add(data.Playtime, day, whole)
	local ranks = PlaytimeLogic.newRanks(after, RANKS)
	if whole <= 0 and data.Playtime.Day == day and #ranks == 0 then
		session.NextEvent = nextEvent(data, day)
		return true
	end
	local saved = PlayerData.update(player, function(d)
		d.Playtime = after
		d.Boosts = BoostsLogic.tick(d.Boosts, whole)
		for _, index in ranks do
			local rank = RANKS[index]
			if rawget(Decor :: any, rank.Decor) then
				d.Decor.Owned[rank.Decor] = true
			end
			d.Playtime.Rank = index
		end
	end)
	if not saved then
		return false
	end
	session.Pending -= whole
	session.NextEvent = nextEvent(data, day)
	if #ranks > 0 then
		rankedUp(player, ranks)
	end
	if #PlaytimeLogic.ready(data.Playtime, day, GIFTS) > readyBefore then
		Remotes.news(player, "🎁 A play gift is ready!")
	end
	publish(player, session, data)
	return true
end

local function markActive(player: Player)
	local session = sessions[player]
	if session then
		session.LastActive = os.clock()
	end
end

local function sample(player: Player, session: Session, now: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	local last = session.LastPos
	if last == nil or (position - last).Magnitude >= MOVE_STUDS then
		if last ~= nil then
			session.LastActive = now
		end
		session.LastPos = position
	end
end

local function countAll()
	local day = today()
	for player, session in sessions do
		local now = os.clock()
		local step = math.clamp(now - session.LastTick, 0, MAX_STEP)
		session.LastTick = now
		if not present(player) then
			continue
		end
		sample(player, session, now)
		local data = PlayerData.get(player)
		local counting = data ~= nil
			and Plots.getPlot(player) ~= nil
			and PlaytimeLogic.active(session.LastActive, now, Config.PlaytimeIdleSeconds)
		if counting then
			session.Pending += step
		end
		if counting ~= session.Counting then
			session.Counting = counting
			player:SetAttribute("PlayCounting", counting)
		end
		if data then
			if data.Playtime.Day ~= day or session.Pending >= session.NextEvent then
				Playtime.commit(player)
			end
			publish(player, session, data)
		end
	end
end

local function begin(player: Player, data: Types.Data)
	if sessions[player] or not present(player) then
		return
	end
	local now = os.clock()
	local session: Session = {
		Pending = 0,
		LastTick = now,
		LastActive = now, -- joining counts as acting
		LastPos = nil,
		NextEvent = 1,
		Counting = false,
	}
	sessions[player] = session
	player:SetAttribute("PlayCounting", false)
	Playtime.commit(player) -- rolls a save from another day over, and pays a rank an Admin edit or migration reached
	publish(player, session, data)
	for index = 1, math.min(data.Playtime.Rank, #RANKS) do
		Badges.awardRoblox(player, RANKS[index].Id) -- in case the badge was made after they got there
	end
	showRank(player)
end

------------------------------------------------------------------------------------------------------------------
-- Admin
------------------------------------------------------------------------------------------------------------------

local function addSeconds(player: Player, seconds: number, todayOnly: boolean): boolean
	if not PlayerData.get(player) or type(seconds) ~= "number" or seconds <= 0 then
		return false
	end
	Playtime.commit(player)
	local day = today()
	local ok = PlayerData.update(player, function(d)
		local rolled = PlaytimeLogic.rollover(d.Playtime, day)
		if todayOnly then
			rolled.TodaySeconds += seconds
			rolled.TotalSeconds = math.max(rolled.TotalSeconds, rolled.TodaySeconds)
		else
			rolled.TotalSeconds += seconds
		end
		d.Playtime = rolled
	end)
	if ok then
		Playtime.commit(player) -- ranks reached, gifts unlocked: the same path as play
	end
	return ok
end

function Playtime.addToday(player: Player, seconds: number): boolean
	return addSeconds(player, seconds, true)
end

function Playtime.addTotal(player: Player, seconds: number): boolean
	return addSeconds(player, seconds, false)
end

------------------------------------------------------------------------------------------------------------------
-- The remote
------------------------------------------------------------------------------------------------------------------

local function claimGift(player: Player, index: any): (boolean, string)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > #GIFTS then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data or not sessions[player] then
		return false, "⏳ One moment!"
	end
	Playtime.commit(player) -- the seconds counted so far
	local day = today()
	local nextSave, gift = PlaytimeLogic.claim(data.Playtime, day, GIFTS, index)
	if not gift then
		local state = PlaytimeLogic.state(data.Playtime, day, GIFTS, index)
		return false, if state == "Claimed" then "✅ Already opened!" else "⏳ Keep playing!"
	end
	-- Mark it opened and pay with no yield in between, so a second request can't pass the same check.
	local boostId = gift.Boost
	local boost = if boostId then rawget(BoostData :: any, boostId) else nil
	local marked = PlayerData.update(player, function(d)
		d.Playtime = nextSave
		if boost and boostId then
			d.Boosts = BoostsLogic.extend(d.Boosts, BoostData, boostId, boost.Minutes * 60, Config.BoostMaxMinutes * 60)
		end
	end)
	if not marked then
		return false, Remotes.OOPS
	end
	if gift.Cash > 0 then
		Economy.addCash(player, gift.Cash)
	end
	if gift.Stars > 0 then
		Progress.addStars(player, gift.Stars)
	end
	local session = sessions[player]
	if session then
		session.NextEvent = nextEvent(data, day)
	end
	local parts = { "🎁 +" .. gift.Cash .. " " .. Config.CurrencyName }
	if gift.Stars > 0 then
		table.insert(parts, "+" .. gift.Stars .. " ⭐")
	end
	if boost then
		table.insert(parts, boost.Icon)
	end
	return true, table.concat(parts, " ")
end

function Playtime.start()
	Boosts.hook(Playtime.pending, function(player: Player)
		Playtime.commit(player)
	end)
	Remotes.setActivity(markActive)
	Remotes.serve("ClaimPlayGift", claimGift)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(_prompt, player)
		markActive(player)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(_prompt, player)
		markActive(player)
	end)

	PlayerData.Loaded:Connect(begin)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			begin(player, data) -- loaded before we were listening
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Runs before PlayerData's leave-save (it waits a frame for handlers like this one), so the rest is saved.
		pcall(Playtime.commit, player)
		sessions[player] = nil
	end)

	Plots.PlotAssigned:Connect(function(player: Player)
		showRank(player)
	end)
	Plots.PlotReleased:Connect(function(_player: Player, plot: Types.Plot)
		local label = rankLabel(plot)
		if label then
			label.Text = ""
			label.Visible = false
		end
	end)

	-- The Studio forward-UtcDay switch (and real midnight, via Daily) rolls the gifts over for everyone right away.
	Workspace:GetAttributeChangedSignal("UtcDay"):Connect(function()
		for player in sessions do
			task.spawn(Playtime.commit, player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(countAll)
			if not ok then
				warn("[Playtime] Tick failed:", err)
			end
		end
	end)
end

return Playtime
