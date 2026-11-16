--!strict
-- PromptFilter: each player sees only the world prompts that are for them (Task 9 integration). Client only.
--   init(ctx)
--
-- A ProximityPrompt made on the server shows for everyone, so the server answers the wrong person with a kind
-- toast. This module hides those prompts on this screen by setting MaxActivationDistance to 0 (the server writes
-- Enabled, never MaxActivationDistance after creating a prompt, so the two never clash):
--   ClinicSignPrompt (Visits)                Audience "Owner": only the plot's owner sees it (the helpers switch).
--                                            Audience "Visitor": everyone but the owner (send a heart).
--   StationPrompt (Stations) and the         only players who may work the clinic: the owner, the owner's Roblox
--   Counter's TreatPrompt (Patients)         friends, or anyone while the plot's OpenHelpers is on.
-- Friend status comes from LocalPlayer:IsFriendsWith, cached per owner. Until it's known (or if it can't be
-- checked) the prompt shows. Nothing here is a security check: the server's Plots.canWork has the last word.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local PromptFilter = {}

local SIGN_TAG = "ClinicSignPrompt" -- Visits.SIGN_PROMPT_TAG (server modules can't be required here)
local STATION_TAG = "StationPrompt" -- Stations.PROMPT_TAG
local TREAT_NAME = "TreatPrompt" -- Patients' prompt on the Counter
local MAKE_NAME = "MakePrompt" -- Stations.PROMPT_NAME
local REACH_ATTRIBUTE = "FilterReach" -- set on this client only

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
		if CollectionService:HasTag(prompt, STATION_TAG) or prompt.Name == TREAT_NAME or prompt.Name == MAKE_NAME then
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

	-- Gone from its plot (destroyed with a room, or streamed out): forget it. If it comes back, DescendantAdded
	-- tracks it again from scratch.
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

	task.spawn(function()
		local clinics = Workspace:WaitForChild("Clinics")
		clinics.DescendantAdded:Connect(track) -- new rooms, streaming, the Counter's prompt
		for _, descendant in clinics:GetDescendants() do
			track(descendant)
		end
	end)
end

return PromptFilter
