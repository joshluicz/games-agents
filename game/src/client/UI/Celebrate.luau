--!strict
-- Big celebration screens (depth-update design §4, build plan §B9). OWNER: T6. Load `game-feel`.
--   init(ctx)   listens for the bus "Celebrate" (info: Types.CelebrateInfo): from the server for a level-up
--               ("LevelUp"), a first-time hire ("NewNurse") and a completed Journal group ("JournalSet"); T6 fires
--               "Room" itself for an unlocked room
-- What T6 builds: full-screen rays + confetti + a big outlined title and icon (Kit.celebrate), the rarity frame for
-- a nurse (Kit.rarityFrame), a sound, then it gets out of the way. One at a time (queue them). Never during the
-- first-session tutorial's quiet steps; calm (Kit.reducedMotion()) = no rays spin, no confetti, a soft pop.
--
-- FOUNDATION STUB: a toast and a fanfare, so the moments are visible before T6 lands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Celebrate = {}

function Celebrate.init(ctx: Types.Ctx)
	ctx.on("Celebrate", function(info: any)
		if type(info) ~= "table" or type(info.Title) ~= "string" then
			return
		end
		local icon = if type(info.Icon) == "string" then info.Icon .. " " else ""
		ctx.toast(icon .. info.Title)
		ctx.fire("Sound", "Fanfare")
	end)
end

return Celebrate
