--!strict
-- PromptFilter: each player sees only the world prompts that are for them (Task 9 integration). Client only.
--   init(ctx)
--
-- A ProximityPrompt made on the server shows for everyone, so the server answers the wrong person with a kind
-- toast. This module hides those prompts on this screen by setting MaxActivationDistance to 0 (the server writes
-- Enabled, never MaxActivationDistance after creating a prompt, so the two never clash):
--   ClinicSignPrompt (Visits)                Audience "Visitor": everyone but the owner (send a heart).
--                                            Audience "Owner": only the plot's owner (none today: the helpers
--                                            switch moved to the HUD's ⚙️ Settings, the SetHelpers remote).
--   StationPrompt (Stations: the supply      only players who may work the clinic: the owner, the owner's Roblox
--   stations and the dispensary's Dispense)  friends, or anyone while the plot's OpenHelpers is on.
--   and each exam bay's BayPrompt (Patients:
--   "Examine" / "Treat", tag TreatPrompt)
--   and each waiting patient's SendPrompt
--   (Patients: "Send", tag TreatPrompt)
--   Progression v2: the lift landings'        the same: "Ride with patient" is work at that clinic (build plan §C
--   EscortPrompt (PlotBuilder, Patients)     T8). The LiftPrompt stays for everyone (anyone may ride a lift).
-- Friend status comes from LocalPlayer:IsFriendsWith, cached per owner. Until it's known (or if it can't be
-- checked) the prompt shows. Nothing here is a security check: the server's Plots.canWork has the last word.
--
-- Finding the prompts costs nothing while the town is busy (depth update perf pass): the sign, station, bay and
-- escort prompts arrive by their CollectionService tags (also when they stream in or a room is bought). A bay or
-- escort prompt that isn't tagged yet is found by name in each plot's Building and Rooms (rebuilt only on a
-- level-up, a theme change or a purchase, so that's a handful of events). Nothing listens to every part added to
-- Workspace.Clinics (each creature, nurse and building floor used to wake it). The Real Clinic removed the
-- Counter's Treat prompt and the hot tub's SoakPrompt: treating happens at the bays. A patient's Send prompt has the
-- same fallback as a bay's: one that isn't tagged yet is found by name, once, as its patient's model arrives in the
-- plot's Patients folder (one event per patient, never one per part).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local PromptFilter = {}

local SIGN_TAG = "ClinicSignPrompt" -- Visits.SIGN_PROMPT_TAG (server modules can't be required here)
local STATION_TAG = "StationPrompt" -- Stations.PROMPT_TAG
local TREAT_TAG = "TreatPrompt" -- Patients' tag on every exam bay's BayPrompt
local BAY_NAME = "BayPrompt" -- the prompt at each ExamBay_<id>'s DoctorSpot ("Examine" / "Treat")
local TREAT_NAME = "TreatPrompt" -- an older name for a treat prompt (still counts as work)
local MAKE_NAME = "MakePrompt" -- Stations.PROMPT_NAME
local REACH_ATTRIBUTE = "FilterReach" -- set on this client only
-- Progression v2 (build plan §B4): the lift's "Ride with patient" prompt on each landing
local ESCORT_NAME = "EscortPrompt"
local ESCORT_TAG = "EscortPrompt" -- its tag, once PlotBuilder/Patients add it (until then: the name watch below)
-- Where an untagged bay or escort prompt is looked for: the plot's Building and its Rooms (the Cozy Ward's bays).
local HOLDER_NAMES = { Building = true, Rooms = true }
local SEND_NAME = "SendPrompt" -- Patients: the "Send" prompt on each waiting patient (simple start: you send them)
local PATIENTS_NAME = "Patients" -- the plot's folder of patient models (Server/Patients)
local WATCHED_NAMES = { [BAY_NAME] = true, [ESCORT_NAME] = true }
local WORK_NAMES = {
	[BAY_NAME] = true,
	[TREAT_NAME] = true,
	[MAKE_NAME] = true,
	[ESCORT_NAME] = true,
	[SEND_NAME] = true,
}

type Kind = "Sign" | "Work"

type Tracked = { Kind: Kind, Plot: Model, Reach: number }

function PromptFilter.init(ctx: Types.Ctx)
	local player = ctx.Player
	-- A strong table, cleaned up by hand when a prompt leaves the clinics. (Weak Instance keys are unreliable in
	-- Roblox: an Instance's Lua wrapper can be collected while the Instance lives on, which would drop the entry
	-- and leave that prompt stuck at whatever reach it had, even 0.)
	local tracked: { [ProximityPrompt]: Tracked } = {}
	local untrack: { [ProximityPrompt]: RBXScriptConnection } = {}
	local friends: { [number]: boolean } = {}
	local asking: { [number]: boolean } = {}

	local function ownerOf(plot: Model): number
		local ownerId = plot:GetAttribute("OwnerUserId")
		return if type(ownerId) == "number" then ownerId else 0
	end

	-- The clinic plot a prompt belongs to: the nearest ancestor Model with an OwnerUserId attribute.
	local function plotOf(prompt: Instance): Model?
		local node = prompt.Parent
		while node and node ~= Workspace do
			if node:IsA("Model") and node:GetAttribute("OwnerUserId") ~= nil then
				return node
			end
			node = node.Parent
		end
		return nil
	end

	local function kindOf(prompt: ProximityPrompt): Kind?
		if CollectionService:HasTag(prompt, SIGN_TAG) then
			return "Sign"
		end
		if
			CollectionService:HasTag(prompt, STATION_TAG)
			or CollectionService:HasTag(prompt, TREAT_TAG)
			or CollectionService:HasTag(prompt, ESCORT_TAG)
			or WORK_NAMES[prompt.Name] == true
		then
			return "Work"
		end
		return nil
	end

	local refreshAll: () -> () -- defined below

	-- true / false once known; nil while unknown (a check is then started).
	local function isFriend(userId: number): boolean?
		local known = friends[userId]
		if known ~= nil then
			return known
		end
		if not asking[userId] then
			asking[userId] = true
			task.spawn(function()
				local ok, result = pcall(player.IsFriendsWith, player, userId)
				friends[userId] = if ok then result == true else true -- can't tell: show it, the server decides
				asking[userId] = nil
				refreshAll()
			end)
		end
		return nil
	end

	local function allowed(prompt: ProximityPrompt, entry: Tracked): boolean
		local ownerId = ownerOf(entry.Plot)
		if ownerId == 0 then
			return true -- a free plot: the server has switched these prompts off anyway
		end
		local mine = ownerId == player.UserId
		if entry.Kind == "Sign" then
			local audience = prompt:GetAttribute("Audience")
			if audience == "Owner" then
				return mine
			elseif audience == "Visitor" then
				return not mine
			end
			return true
		end
		if mine or entry.Plot:GetAttribute("OpenHelpers") == true then
			return true
		end
		return isFriend(ownerId) ~= false
	end

	local function apply(prompt: ProximityPrompt, entry: Tracked)
		local reach = if allowed(prompt, entry) then entry.Reach else 0
		if prompt.MaxActivationDistance ~= reach then
			prompt.MaxActivationDistance = reach
		end
	end

	-- Gone from its plot (destroyed with a room, or streamed out): forget it. If it comes back, its tag signal (or
	-- the name watch) tracks it again from scratch.
	local function forget(prompt: ProximityPrompt)
		tracked[prompt] = nil
		local connection = untrack[prompt]
		untrack[prompt] = nil
		if connection then
			connection:Disconnect()
		end
	end

	-- Applies to every tracked prompt that passes `which`, and forgets any that left its plot (in case the
	-- AncestryChanged clean-up didn't run, e.g. a deferred event dropped by Destroy).
	local function refresh(which: (Tracked) -> boolean)
		local gone: { ProximityPrompt } = {}
		for prompt, entry in tracked do
			if not prompt:IsDescendantOf(entry.Plot) then
				table.insert(gone, prompt)
			elseif which(entry) then
				apply(prompt, entry)
			end
		end
		for _, prompt in gone do
			forget(prompt)
		end
	end

	refreshAll = function()
		refresh(function()
			return true
		end)
	end

	local watchedPlots: { [Model]: boolean } = {} -- the six plots live for the whole session
	local function refreshPlot(plot: Model)
		refresh(function(entry: Tracked)
			return entry.Plot == plot
		end)
	end
	local function watchPlot(plot: Model)
		if watchedPlots[plot] then
			return
		end
		watchedPlots[plot] = true
		for _, attribute in { "OwnerUserId", "OpenHelpers" } do
			plot:GetAttributeChangedSignal(attribute):Connect(function()
				refreshPlot(plot)
			end)
		end
	end

	local function track(instance: Instance)
		if not instance:IsA("ProximityPrompt") or tracked[instance] then
			return
		end
		local kind = kindOf(instance)
		if not kind then
			return
		end
		local plot = plotOf(instance)
		if not plot then
			return
		end
		-- The server's reach, remembered on the prompt (a local attribute), so a prompt that's tracked again
		-- after we zeroed it still gets its real reach back.
		local reach = instance:GetAttribute(REACH_ATTRIBUTE)
		if type(reach) ~= "number" then
			reach = instance.MaxActivationDistance
			instance:SetAttribute(REACH_ATTRIBUTE, reach)
		end
		local entry: Tracked = { Kind = kind, Plot = plot, Reach = reach :: number }
		tracked[instance] = entry
		local prompt = instance
		untrack[prompt] = prompt.AncestryChanged:Connect(function()
			if not prompt:IsDescendantOf(plot) then
				forget(prompt)
			end
		end)
		watchPlot(plot)
		apply(instance, entry)
	end

	-- Tagged prompts: the sign's, every station's (the dispensary's too), every bay's and the lift landings'.
	-- Streaming and new rooms bring theirs in through the same signals. (Deferred: a prompt can arrive a moment
	-- before its plot does.)
	for _, tag in { SIGN_TAG, STATION_TAG, TREAT_TAG, ESCORT_TAG } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			task.defer(track, instance)
		end)
		for _, tagged in CollectionService:GetTagged(tag) do
			track(tagged)
		end
	end

	-- A bay or escort prompt without its tag: inside a plot's Building and Rooms, by name only. Each is rebuilt on a
	-- level-up, a theme change or a purchase (a new one is watched).
	local function trackByName(descendant: Instance)
		if descendant:IsA("ProximityPrompt") and WATCHED_NAMES[descendant.Name] then
			task.defer(track, descendant)
		end
	end
	-- A patient's Send prompt without its tag: looked for by name once, as the patient's model arrives.
	local function trackSend(patient: Instance)
		task.defer(function()
			local prompt = patient:FindFirstChild(SEND_NAME, true)
			if prompt then
				track(prompt)
			end
		end)
	end
	local watchedHolders: { [Instance]: RBXScriptConnection } = {}
	local function watchHolder(holder: Instance)
		if watchedHolders[holder] or not (HOLDER_NAMES[holder.Name] or holder.Name == PATIENTS_NAME) then
			return
		end
		if holder.Name == PATIENTS_NAME then
			watchedHolders[holder] = holder.ChildAdded:Connect(trackSend)
		else
			watchedHolders[holder] = holder.DescendantAdded:Connect(trackByName)
		end
		holder.AncestryChanged:Connect(function()
			if not holder:IsDescendantOf(Workspace) then
				local connection = watchedHolders[holder]
				watchedHolders[holder] = nil
				if connection then
					connection:Disconnect()
				end
			end
		end)
		if holder.Name == PATIENTS_NAME then
			for _, patient in holder:GetChildren() do
				trackSend(patient)
			end
			return
		end
		for _, descendant in holder:GetDescendants() do
			trackByName(descendant)
		end
	end

	local watchedPlotModels: { [Instance]: boolean } = {}
	local function watchPlotModel(plot: Instance)
		if watchedPlotModels[plot] then
			return
		end
		watchedPlotModels[plot] = true
		plot.ChildAdded:Connect(watchHolder) -- a new Building (level-up, theme), Rooms or Patients folder
		for _, child in plot:GetChildren() do
			watchHolder(child)
		end
	end
	task.spawn(function()
		local clinics = Workspace:WaitForChild("Clinics")
		clinics.ChildAdded:Connect(watchPlotModel)
		for _, plot in clinics:GetChildren() do
			watchPlotModel(plot)
		end
	end)
end

return PromptFilter
