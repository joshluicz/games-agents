--!strict
-- Treat sessions: recipes given at the Counter through short mini-games, tips and the combo, Simple mode, and Healer
-- nurses' deliveries (depth-update design §1, build plan §B8). Server only. OWNER: T1.
-- FOUNDATION STUB: SetSimple is real (it's tiny); TreatResult answers "Coming soon!" until T1 lands, and Patients
-- still uses today's one-tap treat.
--
--   Treatment.start()            wires TreatResult and SetSimple; connects Nurses.Heal
--   Treatment.combo(p): number   the player's mini-game combo (the Combo attribute; session-only, never saved)
--   Treatment.simple(p): boolean Data.Simple
-- The flow T1 builds (build plan §B8): TreatPrompt -> the front patient's still-missing recipe items that the helper
-- carries (Carry first, then the plot's nurse tray via Nurses.takeFromTray) -> take them -> State "Treating" ->
-- TreatStart -> TreatResult (or the timeout: all OK) -> Logic/MiniGame.accept (all OK when the helper is farther
-- than Config.Treat.Distance from the Counter) -> Logic/MiniGame.settle with the plot's CheerTip -> the tip
-- (Economy.addCash, capped per cure) -> mark the items given -> complete: bed, recover, Cure.resolve.
-- Security: one open session per player; the session id, the player and the patient must all match; a report
-- sooner than the games' minimum time is all OK; tips are capped per cure; Remotes.serve rate-limits.

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local Nurses = require(script.Parent.Nurses)

local Treatment = {}

function Treatment.combo(player: Player): number
	local combo = player:GetAttribute("Combo")
	return if type(combo) == "number" then combo else 0
end

function Treatment.simple(player: Player): boolean
	local data = PlayerData.get(player)
	return data ~= nil and data.Simple == true
end

local function setSimple(player: Player, on: any): (boolean, string)
	if type(on) ~= "boolean" then
		return false, Remotes.OOPS
	end
	if not PlayerData.get(player) then
		return false, Remotes.OOPS
	end
	PlayerData.update(player, function(data)
		data.Simple = on
	end)
	return true, if on then "👆 Simple taps on!" else "🎮 Mini-games on!"
end

function Treatment.start()
	Remotes.serve("TreatResult", function(_player: Player, _session: any, _ratings: any)
		return false, Remotes.SOON -- T1
	end)
	Remotes.serve("SetSimple", setSimple)
	Nurses.Heal:Connect(function(_plot: any, _nurseId: any)
		-- T1: deliver from the plot's nurse tray to the front patient (rated OK), then Nurses.healed
	end)
end

return Treatment
