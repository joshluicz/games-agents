--!strict
-- Hospital levels: the building grows (memory-20261116-008; depth-update design §3, build plan §B8). Server only.
-- OWNER: T5.
--   Levels.start()                       wires LevelUp; keeps every owned plot's Building (PlotBuilder.buildBuilding)
--                                        and its Level attribute in step with the owner's Data.Level: on
--                                        PlotAssigned, after a level-up, and after any other change to the saved
--                                        level. A released plot goes back to Lv 1 (PlotBuilder.clearPlot)
--   Levels.level(p): number              the player's hospital level (1 until their data loads)
--   Levels.levelUp(p): (ok, message)     the LevelUp remote (its arguments are ignored): a plot, then
--                                        Logic/Levels.canLevelUp (⭐ is a gate, 💰 is spent), then Economy.charge
--                                        spends the cash and sets Data.Level in ONE PlayerData.update;
--                                        Economy.Purchased(p, "Level", "<level>"); the building grows; the
--                                        Celebrate remote ({ Kind = "LevelUp", Title = the level's name, Icon,
--                                        Level }); LevelChanged
--   Levels.slots(p) · Levels.queueCap(p) · Levels.recipeCap(p) · Levels.beds(p)   numbers from Data/Levels
--   Levels.LevelChanged                  signal (p, level, previous): once per change of a player's level (a
--                                        level-up, or the save changed some other way), never for the level a
--                                        player joins at
-- ⭐ is a gate (needed, not spent) and 💰 is spent (build plan §B5, open point §E1). Replies are 6 words or fewer.
--
-- Studio test switch: workspace:SetAttribute("PreviewLevel", n) shows every plot's Building at level n (1-5), so
-- each shell can be looked at without earning it. Only the building changes (its extra beds work): nothing is
-- saved, and slots, the line and recipes still follow the real level. Set it to nil to go back. A live server
-- ignores it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local LevelsData = require(Shared.Data.Levels)
local LevelsLogic = require(Shared.Logic.Levels)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Economy = require(script.Parent.Economy)
local PlotBuilder = require(script.Parent.PlotBuilder)

local Levels = {}

Levels.LevelChanged = Signal.new()

local PREVIEW_ATTRIBUTE = "PreviewLevel"

local MSG = table.freeze({
	Loading = "Still loading! Try again.",
	NoPlot = "Wait for a free clinic!",
	Oops = Remotes.OOPS,
})

-- The level each loaded player was last seen at, so LevelChanged fires once per change.
local known: { [Player]: number } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

function Levels.level(player: Player): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return if data then LevelsLogic.clamp(LevelsData, data.Level) else 1
end

function Levels.slots(player: Player): number
	return LevelsLogic.slots(LevelsData, Levels.level(player))
end

function Levels.queueCap(player: Player): number
	return LevelsLogic.queue(LevelsData, Levels.level(player))
end

function Levels.recipeCap(player: Player): number
	return LevelsLogic.recipeCap(LevelsData, Levels.level(player))
end

function Levels.beds(player: Player): number
	return LevelsLogic.beds(LevelsData, Levels.level(player))
end

------------------------------------------------------------------------------------------------------------------
-- The building on the plot
------------------------------------------------------------------------------------------------------------------

local function previewLevel(): number?
	if not RunService:IsStudio() then
		return nil
	end
	local value = Workspace:GetAttribute(PREVIEW_ATTRIBUTE)
	return if type(value) == "number" then LevelsLogic.clamp(LevelsData, value) else nil
end

-- Builds a plot's Building for `level` unless it already shows it. grewFrom = the level before a level-up, so the
-- Building says what's new (PlotBuilder: GrewFrom, GrewAt).
local function show(plot: Types.Plot, level: number, grewFrom: number?)
	local shown = previewLevel() or level
	local building = plot.Model:FindFirstChild("Building")
	if building and building:GetAttribute("Level") == shown and plot.Model:GetAttribute("Level") == shown then
		return
	end
	local ok, err = pcall(PlotBuilder.buildBuilding, plot.Model, shown, if previewLevel() then nil else grewFrom)
	if not ok then
		warn("[Levels] Could not build the hospital on plot " .. plot.Index .. ":", err)
		plot.Model:SetAttribute("Level", shown)
	end
end

-- Brings everything in step with the player's saved level: their plot's Building, and LevelChanged on a change.
local function sync(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local level = LevelsLogic.clamp(LevelsData, data.Level)
	local previous = known[player]
	known[player] = level
	local plot = Plots.getPlot(player)
	if plot then
		show(plot, level, if previous and previous < level then previous else nil)
	end
	if previous and previous ~= level then
		Levels.LevelChanged:Fire(player, level, previous)
	end
end

local function showAll()
	for _, plot in Plots.all() do
		local owner = plot.Owner
		show(plot, if owner then Levels.level(owner) else 1, nil)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Levelling up
------------------------------------------------------------------------------------------------------------------

-- Arguments are untrusted (the LevelUp remote passes none; anything extra is ignored).
function Levels.levelUp(player: Player): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	-- The building grows on your own plot, so a player without one (all 6 taken) waits for one.
	local plot = Plots.getPlot(player)
	if not plot then
		return false, MSG.NoPlot
	end
	local ok, message = LevelsLogic.canLevelUp(data, LevelsData) -- "Max level!", "Need ⭐45", "Need 💰1500"
	if not ok then
		return false, message
	end
	local previous = LevelsLogic.clamp(LevelsData, data.Level)
	local level = previous + 1
	local row = LevelsData[level]
	-- Nothing yields between that check and this update, so the cash and the level land together or not at all.
	local charged = Economy.charge(player, row.Cash, function(d)
		d.Level = level
	end)
	if not charged then
		return false, MSG.Oops -- the save is closing (they're leaving): nothing changed
	end
	Economy.Purchased:Fire(player, "Level", tostring(level))
	sync(player) -- the building grows (PlayerData.Changed may have done it already)
	local info: Types.CelebrateInfo = { Kind = "LevelUp", Title = row.Name, Icon = row.Icon, Level = level }
	local sent, err = pcall(function()
		Remotes.Celebrate:FireClient(player, info)
	end)
	if not sent then
		warn("[Levels] Celebrate failed:", err)
	end
	return true, row.Icon .. " " .. row.Name .. "!"
end

function Levels.start()
	Remotes.serve("LevelUp", function(player: Player)
		return Levels.levelUp(player)
	end)

	Plots.PlotAssigned:Connect(function(player: Player)
		sync(player)
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		sync(player)
	end)
	-- Any change to the save: cheap when the level is the same (two attribute reads).
	PlayerData.Changed:Connect(function(player: Player)
		sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		known[player] = nil
	end)
	-- Plots handed out before this started (a fast load).
	for _, plot in Plots.all() do
		if plot.Owner then
			sync(plot.Owner)
		end
	end

	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal(PREVIEW_ATTRIBUTE):Connect(showAll)
		-- A released plot is cleared back to Lv 1 right after PlotReleased; put the preview back on it.
		Plots.PlotReleased:Connect(function(_player: Player, plot: Types.Plot)
			if previewLevel() then
				task.defer(show, plot, 1, nil)
			end
		end)
		if previewLevel() then
			warn("[Levels] PreviewLevel is on: every plot shows a level-" .. tostring(previewLevel()) .. " building")
			showAll()
		end
	end
end

return Levels
