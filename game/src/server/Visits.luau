--!strict
-- Visiting other clinics: hearts, the helpers switch and the friend referral (build plan §B5, design §5.9).
-- Server only.
--
-- Hearts: one small prompt on every plot's Sign, on while the plot has an owner.
--   HeartPrompt (E / ButtonX, hold 0.3 s, Audience "Visitor")  anyone but the owner leaves a heart: once per owner
--               per UTC day (saved in the giver's HeartsGiven). The owner's saved HeartsReceived, the plot's Hearts
--               attribute and the sign's "❤️ <n>" go up, the sign sparkles, and the owner gets a toast.
--   It shows only within 6 studs, low and to one side of the board (HeartAnchor) and nudged off it (UIOffset), so it
--   never covers the sign's words or the scene (Joshua: "the pop up is so obvious that it hides the rest of the
--   things behind"). A ProximityPrompt shows for everyone, so it also answers the owner kindly; it carries the
--   CollectionService tag SIGN_PROMPT_TAG and an `Audience` attribute, so Client/UI/PromptFilter hides it from the
--   owner.
-- The helpers switch: the RemoteFunction SetHelpers(on: boolean), from the owner's ⚙️ Settings panel (Client/UI/Hud
--   "👥 Friends only" / "🤝 Anyone can help"). Only a plot's owner may call it; it sets the plot's OpenHelpers (off =
--   only the owner and their Roblox friends may work the clinic, on = anyone; Plots.canWork reads it) and toasts.
--   Rate-limited (Remotes.serve) with a 1 s cooldown per player. Off on every new owner (Plots).
--
-- Referral: a player who joins through a friend's invite (Player:GetJoinData().ReferredByPlayerId) gets the
-- FriendBench decor once per account (Data.ReferralRewarded), and the friend who invited them gets one too if
-- they're in this server and don't own it yet. Join data can be client-influenced (Creator Hub, Player
-- GetJoinData), so the reward is cosmetic, once, and the id is checked: a positive whole number, not yourself.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Decor = require(Shared.Data.Decor)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Daily = require(script.Parent.Daily)
local Badges = require(script.Parent.Badges) -- playtime branch: hearts count for ❤️ Friendly

local Visits = {}

Visits.SIGN_PROMPT_TAG = "ClinicSignPrompt"
Visits.REFERRAL_DECOR = "FriendBench"

local PROMPT_DISTANCE = 6 -- the heart prompt shows only once you've walked up to the sign
local PROMPT_HOLD = 0.3 -- a short hold, so walking past with the key down never sends one
local PROMPT_HEIGHT = 2.6 -- its anchor sits about this high above the plot's ground (never above the board's middle)
local PROMPT_NUDGE = Vector2.new(64, 0) -- and its pop-up this many pixels further out, away from the words
local DISTANCE_SLACK = 8 -- lag and the prompt's own reach
local TOGGLE_COOLDOWN = 1
local BURST_SECONDS = 0.3

local lastToggle: { [Player]: number } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function near(player: Player, anchor: Attachment): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - anchor.WorldPosition).Magnitude <= PROMPT_DISTANCE + DISTANCE_SLACK
end

local function heartLabel(plot: Types.Plot): TextLabel?
	local sign = plot.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("HeartCount")
	return if label and label:IsA("TextLabel") then label else nil
end

local function hearts(plot: Types.Plot): number
	local value = plot.Model:GetAttribute("Hearts")
	return if type(value) == "number" and value == value then value else 0
end

local function isOwned(plot: Types.Plot): boolean
	local ownerId = plot.Model:GetAttribute("OwnerUserId")
	return type(ownerId) == "number" and ownerId ~= 0
end

------------------------------------------------------------------------------------------------------------------
-- Sign prompts
------------------------------------------------------------------------------------------------------------------

type SignPrompts = {
	Heart: ProximityPrompt,
	HeartAnchor: Attachment,
	Burst: ParticleEmitter,
}

local function makeBurst(anchor: Attachment): ParticleEmitter
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "HeartBurst"
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 200, 220))
	burst.LightEmission = 0.6
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.6, 1)
	burst.Speed = NumberRange.new(4, 7)
	burst.SpreadAngle = Vector2.new(50, 50)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Rate = 60
	burst.Enabled = false
	burst.Parent = anchor
	return burst
end

local function buildPrompts(plot: Types.Plot, sign: BasePart): SignPrompts
	-- In front of the face the SignGui is drawn on (the street side).
	local gui = sign:FindFirstChild("SignGui")
	local face = if gui and gui:IsA("SurfaceGui") then gui.Face else Enum.NormalId.Front
	local normal = Vector3.FromNormalId(face)
	local across = if math.abs(normal.X) > 0.5 then Vector3.zAxis else Vector3.xAxis
	local front = normal * (math.abs(normal:Dot(sign.Size)) / 2 + 0.4)
	-- The heart prompt's anchor: toward the right end of the board as you face it (away from the gate on the
	-- placeholder plot), and dropped to about chest height, so under a raised board its pop-up sits below and beside
	-- the words. On a low sign it stays level with the board's middle. Its UIOffset pushes it further right.
	local beside = front - across * (math.abs(across:Dot(sign.Size)) * 0.3)
	local groundY = plot.Model:GetPivot().Y
	local drop = math.min(0, groundY + PROMPT_HEIGHT - sign.CFrame:PointToWorldSpace(beside).Y)

	local heartAnchor = Instance.new("Attachment")
	heartAnchor.Name = "HeartAnchor"
	heartAnchor.Position = beside + sign.CFrame:VectorToObjectSpace(Vector3.new(0, drop, 0))
	heartAnchor.Parent = sign

	local burstAnchor = Instance.new("Attachment") -- the heart sparkles come off the board itself
	burstAnchor.Name = "HeartBurstAnchor"
	burstAnchor.Position = front
	burstAnchor.Parent = sign

	local heart = Instance.new("ProximityPrompt")
	heart.Name = "HeartPrompt"
	heart.ActionText = "❤️ Send a heart"
	heart.ObjectText = "" -- one line: a smaller pop-up
	heart.KeyboardKeyCode = Enum.KeyCode.E
	heart.GamepadKeyCode = Enum.KeyCode.ButtonX
	heart.HoldDuration = PROMPT_HOLD
	heart.MaxActivationDistance = PROMPT_DISTANCE
	heart.RequiresLineOfSight = false -- the fence rails would make it flicker
	heart.UIOffset = PROMPT_NUDGE
	heart.Enabled = false
	heart:SetAttribute("Audience", "Visitor") -- PromptFilter hides it from the owner
	CollectionService:AddTag(heart, Visits.SIGN_PROMPT_TAG)
	heart.Parent = heartAnchor

	return {
		Heart = heart,
		HeartAnchor = heartAnchor,
		Burst = makeBurst(burstAnchor),
	}
end

local function refreshSign(plot: Types.Plot, prompts: SignPrompts)
	local owned = isOwned(plot)
	prompts.Heart.Enabled = owned
	local label = heartLabel(plot)
	if label then
		label.Text = if owned then "❤️ " .. hearts(plot) else ""
	end
end

local function sparkle(prompts: SignPrompts)
	prompts.Burst.Enabled = true
	task.delay(BURST_SECONDS, function()
		prompts.Burst.Enabled = false
	end)
end

local function onHeart(plot: Types.Plot, prompts: SignPrompts, player: Player)
	if not Remotes.allow(player, "Heart") then
		return
	end
	local owner = plot.Owner
	if not owner or owner.Parent ~= Players or not near(player, prompts.HeartAnchor) then
		return
	end
	if player == owner then
		Remotes.toast(player, "💛 Visitors leave hearts here!")
		return
	end
	local data = PlayerData.get(player)
	if not data then
		Remotes.toast(player, "⏳ One moment!")
		return
	end
	local today = Daily.today()
	local key = tostring(owner.UserId)
	if data.HeartsGiven.Day == today and data.HeartsGiven.Plots[key] then
		Remotes.toast(player, "❤️ Sent today! Come back tomorrow")
		return
	end
	-- Check and mark with no yield in between, so two quick presses give one heart.
	local marked = PlayerData.update(player, function(d)
		if d.HeartsGiven.Day ~= today then
			d.HeartsGiven.Day = today
			d.HeartsGiven.Plots = {}
		end
		d.HeartsGiven.Plots[key] = true
	end)
	if not marked then
		return
	end
	-- Saved with the owner (Data.HeartsReceived), so the sign keeps its count across sessions.
	local total = hearts(plot) + 1
	PlayerData.update(owner, function(d)
		d.HeartsReceived += 1
		total = d.HeartsReceived
	end)
	plot.Model:SetAttribute("Hearts", total)
	pcall(Badges.onHeart, player) -- playtime branch
	sparkle(prompts)
	Remotes.toast(player, "❤️ Heart sent!")
	Remotes.news(owner, "❤️ " .. player.DisplayName .. " loves your clinic!")
end

------------------------------------------------------------------------------------------------------------------
-- The helpers switch (SetHelpers, from the owner's ⚙️ Settings)
------------------------------------------------------------------------------------------------------------------

-- SetHelpers(on): the caller's own clinic only. `on` must be a boolean: true = anyone may help, false = friends.
local function setHelpers(player: Player, on: any): (boolean, string)
	if type(on) ~= "boolean" then
		return false, Remotes.OOPS
	end
	local plot = Plots.getPlot(player)
	if not plot or plot.Owner ~= player then
		return false, "🏠 No clinic yet!"
	end
	local now = os.clock()
	if now - (lastToggle[player] or 0) < TOGGLE_COOLDOWN then
		return false, Remotes.TOO_FAST
	end
	lastToggle[player] = now
	plot.Model:SetAttribute("OpenHelpers", on)
	Remotes.toast(player, if on then "🤝 Anyone can help now!" else "🔒 Only friends can help now")
	return true, ""
end

local function wireSign(plot: Types.Plot)
	local sign = plot.Model:FindFirstChild("Sign")
	if not (sign and sign:IsA("BasePart")) then
		warn("[Visits] Plot_" .. plot.Index .. " has no Sign part: no hearts there")
		return
	end
	local prompts = buildPrompts(plot, sign)
	prompts.Heart.Triggered:Connect(function(player: Player)
		onHeart(plot, prompts, player)
	end)
	for _, attribute in { "OwnerUserId", "Hearts" } do
		plot.Model:GetAttributeChangedSignal(attribute):Connect(function()
			refreshSign(plot, prompts)
		end)
	end
	refreshSign(plot, prompts)
end

------------------------------------------------------------------------------------------------------------------
-- Referral
------------------------------------------------------------------------------------------------------------------

local function referrerOf(player: Player): number?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	local id = joinData.ReferredByPlayerId
	if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or id <= 0 or id == player.UserId then
		return nil
	end
	return id
end

-- Gives the decor if the player doesn't own it yet. Returns true when it was new.
local function giveDecor(player: Player, decorId: string): boolean
	local data = PlayerData.get(player)
	if not data or data.Decor.Owned[decorId] then
		return false
	end
	return PlayerData.update(player, function(d)
		d.Decor.Owned[decorId] = true
	end)
end

local function checkReferral(player: Player)
	local decorId = Visits.REFERRAL_DECOR
	if not rawget(Decor :: any, decorId) then
		return
	end
	local data = PlayerData.get(player)
	local referrerId = referrerOf(player)
	if not data or data.ReferralRewarded or not referrerId then
		return
	end
	local isNew = not data.Decor.Owned[decorId]
	PlayerData.update(player, function(d)
		d.ReferralRewarded = true
		d.Decor.Owned[decorId] = true
	end)
	local icon = (Decor :: any)[decorId].Icon -- the same icon the Shop and the Book show
	if isNew then
		Remotes.news(player, icon .. " Friend Bench! Thanks for coming!")
	end
	local referrer = Players:GetPlayerByUserId(referrerId)
	if referrer and giveDecor(referrer, decorId) then
		Remotes.news(referrer, icon .. " Friend Bench! Thanks for inviting!")
	end
end

------------------------------------------------------------------------------------------------------------------

function Visits.start()
	for _, plot in Plots.all() do
		wireSign(plot)
	end
	Remotes.serve("SetHelpers", setHelpers)

	PlayerData.Loaded:Connect(function(player: Player)
		if isPlayer(player) then
			checkReferral(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			task.spawn(checkReferral, player) -- loaded before we were listening
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
	end)
end

return Visits
