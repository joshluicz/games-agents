--!strict
-- Regulars with stories: three returning patients, five beats each (build plan §B5, design §5.7). Server only;
-- the rules are in Shared/Logic/Story (Lune-tested).
--
--   Story.dueRegular(owner): RegularId?
--       Patients asks this when choosing whom to spawn on the owner's plot. A non-nil answer reserves that
--       regular for this visit, so ask only when you'll spawn the answer.
--   Story.onCure(owner, regularId?)
--       Cure.resolve calls it (nil = not a regular). One beat per regular per UTC day; the last beat grants the
--       Reward (decor owned and put on show, or a room unlocked free via Plots.unlockRoom) with a toast.
--   Story.bubble(owner, regularId): { Emote, Bubble }
--       what the regular says on this visit (the beat they're about to tell).
-- Extras:
--   Story.left(owner, regularId)   a regular left without a cure (patience ran out): they come back later
--   Story.today(): number          the UTC story day
--
-- Rules (design §5.7):
--   · A story day is a real UTC day. Each regular visits at most once per day; missed days skip nothing.
--   · Regulars unlock by Clinic Stars (Data/Regulars UnlockStars), then move forward in parallel.
--   · One regular on a plot at a time, with a short gap between them. A Night-wing regular only comes at night.
--   · A brand-new clinic gets its first ordinary patient before the first regular walks in.
--   · Rewards are granted exactly once: the reward is written in the same save update as the last beat, and on
--     load any finished story whose reward is missing is repaired (owned rewards are never granted twice).
--   · DizzyComet's finished story also lights the owner's clinic sign with a comet star (plan §B2: "lights your
--     sign"), which glows at night through PlotBuilder.NIGHT_LIGHT_TAG.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local StoryLogic = require(Shared.Logic.Story)
local DailyLogic = require(Shared.Logic.Daily)
local Regulars = require(Shared.Data.Regulars)
local Decor = require(Shared.Data.Decor)
local Rooms = require(Shared.Data.Rooms)
local Upgrades = require(Shared.Data.Upgrades)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local PlotBuilder = require(script.Parent.PlotBuilder)
local Book = require(script.Parent.Book)

local Story = {}

-- How long a reserved regular holds the plot's "regular slot" if we never hear back (no cure, no left()):
-- the longest patience twice over (time in the queue, then at the counter), plus the bed and a walk.
local MAX_PATIENCE = Config.PatienceSeconds + Config.ChairsPatienceBonus * #Upgrades.Chairs.Prices
local VISIT_HOLD_SECONDS = math.max(180, MAX_PATIENCE * 2 + Config.RecoverSeconds + 30)
local GAP_SECONDS = 30 -- between one regular leaving and the next walking in
local STILL_HERE_SECONDS = 10 -- re-check interval while a reserved regular is still on the plot

local SIGN_GLOW_REGULAR = "DizzyComet"
local SIGN_GLOW_NAME = "CometStar"
local SIGN_GLOW_COLOR = Color3.fromHex("#FFE27A")

local DEFAULT_BUBBLE = table.freeze({ Emote = "🙂", Bubble = "" })

type Visit = {
	Id: string?, -- the reserved regular; nil = in the gap after a visit
	Until: number, -- os.clock() until which no new regular is picked
	Seen: boolean, -- spotted on the plot (needs a Regular or PatientId attribute on the patient model)
}

local visits: { [Player]: Visit } = {}
local unlockedCount: { [Player]: number } = {}

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function regularOf(id: any): Types.Regular?
	if type(id) ~= "string" then
		return nil
	end
	return rawget(Regulars :: any, id)
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

function Story.today(): number
	local computed = DailyLogic.day(os.time())
	local attribute = Workspace:GetAttribute("UtcDay")
	-- Daily keeps Workspace.UtcDay fresh; a forward-set UtcDay (testing) wins, a stale one never holds us back.
	if type(attribute) == "number" and attribute > computed then
		return attribute
	end
	return computed
end

-- A brand-new clinic cures one ordinary patient before the first regular arrives (the first cure is the tutorial).
local function hasStarted(data: Types.Data): boolean
	return data.Stars >= 1 or data.Cured >= 1 or next(data.Book) ~= nil
end

-- Is this regular's creature on the owner's plot right now? Patients tags patient models with a `Regular`
-- (or `PatientId`) attribute; without either this is always false and the visit hold times out instead.
local function onPlot(owner: Player, regularId: string): boolean
	local plot = Plots.getPlot(owner)
	local folder = plot and plot.Model:FindFirstChild("Patients")
	if not folder then
		return false
	end
	for _, child in folder:GetChildren() do
		if child:GetAttribute("Regular") == regularId or child:GetAttribute("PatientId") == regularId then
			return true
		end
	end
	return false
end

local function endVisit(owner: Player, regularId: string)
	local visit = visits[owner]
	if visit and visit.Id == regularId then
		visits[owner] = { Id = nil, Until = os.clock() + GAP_SECONDS, Seen = false }
	end
end

------------------------------------------------------------------------------------------------------------------
-- The comet star on the sign
------------------------------------------------------------------------------------------------------------------

local function addSignGlow(plot: Types.Plot)
	local sign = plot.Model:FindFirstChild("Sign")
	if not (sign and sign:IsA("BasePart")) or sign:FindFirstChild(SIGN_GLOW_NAME) then
		return
	end
	local star = Instance.new("Part")
	star.Name = SIGN_GLOW_NAME
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.new(1.6, 1.6, 1.6)
	star.Color = SIGN_GLOW_COLOR
	star.Material = Enum.Material.SmoothPlastic
	star.Anchored = true
	star.CanCollide = false
	star.CanTouch = false
	star.CanQuery = false
	star.CastShadow = false
	star.CFrame = sign.CFrame * CFrame.new(0, sign.Size.Y / 2 + 1.4, 0)

	local light = Instance.new("PointLight")
	light.Color = SIGN_GLOW_COLOR
	light.Brightness = 1.6
	light.Range = 16
	light.Shadows = false
	light.Enabled = false -- the night-light tag turns it on at night
	light.Parent = star

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(SIGN_GLOW_COLOR)
	sparkle.LightEmission = 1
	sparkle.Rate = 3
	sparkle.Lifetime = NumberRange.new(1, 1.6)
	sparkle.Speed = NumberRange.new(0.4, 1.2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.Parent = star

	star:SetAttribute("Regular", SIGN_GLOW_REGULAR)
	star.Parent = sign
	CollectionService:AddTag(star, PlotBuilder.NIGHT_LIGHT_TAG)
end

local function removeSignGlow(plot: Types.Plot)
	local sign = plot.Model:FindFirstChild("Sign")
	local star = sign and sign:FindFirstChild(SIGN_GLOW_NAME)
	if star then
		star:Destroy()
	end
end

local function refreshSignGlow(owner: Player, plot: Types.Plot)
	local data = PlayerData.get(owner)
	local regular = regularOf(SIGN_GLOW_REGULAR)
	if data and regular and StoryLogic.finished(data.Story[SIGN_GLOW_REGULAR], regular.Beats) then
		addSignGlow(plot)
	else
		removeSignGlow(plot)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Rewards
------------------------------------------------------------------------------------------------------------------

local function rewardLabel(regular: Types.Regular): string
	local item: any = if regular.RewardKind == "Room"
		then rawget(Rooms :: any, regular.Reward)
		else rawget(Decor :: any, regular.Reward)
	if item then
		return item.Icon .. " " .. item.Name
	end
	return "🎁"
end

local function finishStory(owner: Player, regularId: string, regular: Types.Regular, granted: boolean)
	if granted then
		-- e.g. "🎉 Story done! 🌱 Sprout Mascot" (on-screen words stay at 6 or fewer)
		Remotes.toast(owner, "🎉 Story done! " .. rewardLabel(regular))
		if regular.RewardKind ~= "Room" then
			Book.placeReward(owner, regular.Reward)
		end
	else
		Remotes.toast(owner, "🎉 " .. regular.Name .. "'s story done!")
	end
	if regularId == SIGN_GLOW_REGULAR then
		local plot = Plots.getPlot(owner)
		if plot then
			addSignGlow(plot)
		end
	end
end

-- Grants any finished story's missing reward (quietly). Owned rewards are skipped, so it never double-grants.
local function repairRewards(player: Player, data: Types.Data)
	local missing = StoryLogic.unrewarded(Regulars, data.Story, data.Decor.Owned, data.Rooms)
	if #missing == 0 then
		return
	end
	local rooms: { string } = {}
	local saved = PlayerData.update(player, function(d)
		for _, regularId in missing do
			local regular = regularOf(regularId)
			if regular and regular.RewardKind == "Room" then
				table.insert(rooms, regular.Reward)
			elseif regular and rawget(Decor :: any, regular.Reward) then
				d.Decor.Owned[regular.Reward] = true
			end
		end
	end)
	if saved then
		for _, roomId in rooms do
			Plots.unlockRoom(player, roomId)
		end
	end
end

-- "💌 Grumpy Teapot wants to visit!" when Stars cross a regular's UnlockStars (never for ones already unlocked).
local function announceUnlocks(player: Player, data: Types.Data)
	local unlocked = StoryLogic.unlocked(Regulars, data.Stars)
	local before = unlockedCount[player]
	unlockedCount[player] = #unlocked
	if before == nil or #unlocked <= before then
		return
	end
	for index = before + 1, #unlocked do
		local regular = regularOf(unlocked[index])
		if regular then
			Remotes.toast(player, "💌 " .. regular.Name .. " wants to visit!")
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Story.dueRegular(owner: Player): string?
	if not isPlayer(owner) then
		return nil
	end
	local data = PlayerData.get(owner)
	if not data or not hasStarted(data) then
		return nil
	end

	local now = os.clock()
	local visit = visits[owner]
	if visit and visit.Id then
		if onPlot(owner, visit.Id) then
			visit.Seen = true
			visit.Until = math.max(visit.Until, now + STILL_HERE_SECONDS)
			return nil
		elseif visit.Seen then
			endVisit(owner, visit.Id) -- they were here and have gone (patience ran out): short gap, then the next
			visit = visits[owner]
		end
	end
	if visit and now < visit.Until then
		return nil
	end

	local isNight = Workspace:GetAttribute("IsNight") == true
	local regularId = StoryLogic.nextDue(Regulars, data.Story, data.Stars, Story.today(), isNight)
	if regularId then
		visits[owner] = { Id = regularId, Until = now + VISIT_HOLD_SECONDS, Seen = false }
	else
		visits[owner] = nil
	end
	return regularId
end

function Story.onCure(owner: Player, regularId: string?)
	local regular = regularOf(regularId)
	if not regular or not regularId or not isPlayer(owner) then
		return
	end
	endVisit(owner, regularId)

	local data = PlayerData.get(owner)
	if not data then
		return
	end
	local today = Story.today()
	local entry = data.Story[regularId]
	-- One beat per UTC day: a second cure the same day changes nothing. A finished story stays finished.
	if
		StoryLogic.finished(entry, regular.Beats)
		or not StoryLogic.due(entry, today)
		or data.Stars < regular.UnlockStars
	then
		return
	end

	local nextEntry = StoryLogic.advance(entry, today)
	local done = StoryLogic.finished(nextEntry, regular.Beats)
	local granted = false
	local saved = PlayerData.update(owner, function(d)
		d.Story[regularId] = nextEntry
		-- The decor reward lands in the same update as the last beat: it can't be lost or granted twice.
		if done and regular.RewardKind ~= "Room" and rawget(Decor :: any, regular.Reward) then
			granted = not d.Decor.Owned[regular.Reward]
			d.Decor.Owned[regular.Reward] = true
		end
	end)
	if not saved then
		return -- the owner is leaving (their save is closing): nothing changed, so nothing to announce
	end
	if done and regular.RewardKind == "Room" then
		granted = Plots.unlockRoom(owner, regular.Reward) -- false if they already bought it
	end

	if done then
		finishStory(owner, regularId, regular, granted)
	else
		Remotes.toast(
			owner,
			string.format("👋 %s: see you tomorrow! (%d/%d)", regular.Name, nextEntry.Beat, #regular.Beats)
		)
	end
end

function Story.bubble(owner: Player, regularId: string): { Emote: string, Bubble: string }
	local regular = regularOf(regularId)
	if not regular or #regular.Beats == 0 then
		return table.clone(DEFAULT_BUBBLE)
	end
	local data = if isPlayer(owner) then PlayerData.get(owner) else nil
	local entry = data and data.Story[regularId :: string]
	local beat = regular.Beats[StoryLogic.beat(entry, Story.today(), regular.Beats)]
	return { Emote = beat.Emote, Bubble = beat.Bubble }
end

function Story.left(owner: Player, regularId: string)
	if isPlayer(owner) and regularOf(regularId) then
		endVisit(owner, regularId)
	end
end

function Story.start()
	PlayerData.Loaded:Connect(repairRewards)
	PlayerData.Changed:Connect(announceUnlocks)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			task.spawn(repairRewards, player, data)
		end
	end

	Plots.PlotAssigned:Connect(function(player: Player, plot: Types.Plot)
		refreshSignGlow(player, plot)
	end)
	Plots.PlotReleased:Connect(function(player: Player, plot: Types.Plot)
		visits[player] = nil
		removeSignGlow(plot)
	end)
	for _, plot in Plots.all() do
		if plot.Owner then
			refreshSignGlow(plot.Owner, plot)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		visits[player] = nil
		unlockedCount[player] = nil
	end)
end

return Story
