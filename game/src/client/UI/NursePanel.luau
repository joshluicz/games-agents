--!strict
-- The 👩‍⚕️ Nurses panel: the Nurse Journal first, and equipping inside it (depth-update design §2, build plan §B9).
-- OWNER: T4. Load `roblox-ui` and `game-ui-ux`.
--   init(ctx)   opens on ctx.fire("Open", "Nurses") (the Hud's 👩‍⚕️ button); listens for "NurseNews"; fires
--               "NursesNew" (count) for the button's dot
-- What T4 builds (Hud.modal shell): every Data/Nurses entry grouped by rarity (Data/Rarities.Order) with its rarity
-- frame (Kit.rarityFrame): a dark silhouette until Seen (NurseIndex), full colour once Hired, with its level and
-- role; the completion % (Logic/Nurse.journal) and each group's reward (Data/Rarities Journal, ✅ once in
-- JournalSets); equip/unequip on hired nurses (EquipNurse via Hud.ask), slots = Logic/Levels.slots(Data.Levels,
-- State.Level) shown as filled/empty slot chips; a "NEW!" tag on news you haven't opened; a hire celebration.
--
-- FOUNDATION STUB: counts Journal news for the dot and says "coming soon" when opened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local NursePanel = {}

function NursePanel.init(ctx: Types.Ctx)
	local unseen = 0
	ctx.on("NurseNews", function(info: any)
		if type(info) == "table" and (info.Kind == "Seen" or info.Kind == "Hired") then
			unseen += 1
			ctx.fire("NursesNew", unseen)
		end
	end)
	ctx.on("Open", function(name: any)
		if name ~= "Nurses" then
			return
		end
		unseen = 0
		ctx.fire("NursesNew", 0)
		ctx.toast("👩‍⚕️ Coming soon!")
	end)
end

return NursePanel
