--!strict
-- A station's floating icon badge (IconGui, 2.6 studs, sized in studs) hides while the camera is right next to it.
-- Client only. Found in the Real Clinic Studio test (2026-11-17): in the small X-ray room the camera sits ~4.7 studs
-- from the Cast Table's badge, which then filled half the screen during the X-ray game. Close up you are at the
-- station anyway (its prompt shows), so the badge has nothing to tell you.
-- A badge is a BillboardGui named IconGui on a part with a StationId attribute (Server/HospitalBuilder's Station_<id>
-- parts, Server/PlotBuilder's room stations). It hides under HIDE studs and comes back over SHOW (no flicker at
-- the edge). Only badges this module hid are shown again, so a badge the server switched off stays off. Nothing
-- replicates. Checked CHECKS_PER_SECOND times a second.
--
--   NearIcons.init(ctx)   starts the watcher
--   NearIcons.Pure        hidden(distance, wasHidden): tests/NearIcons.spec loads the PURE block

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local NearIcons = {}

-- PURE-BEGIN
local Pure = {}

Pure.HIDE = 7 -- studs from the camera: closer than this, the badge hides
Pure.SHOW = 8 -- and it comes back once the camera is this far again
Pure.CHECKS_PER_SECOND = 5

-- Whether a badge `distance` studs from the camera is hidden, given whether it was hidden last check.
function Pure.hidden(distance: number, wasHidden: boolean): boolean
	if distance ~= distance then -- NaN: leave it as it was
		return wasHidden
	end
	if wasHidden then
		return distance < Pure.SHOW
	end
	return distance < Pure.HIDE
end
-- PURE-END

NearIcons.Pure = Pure

local BADGE = "IconGui"
local TAG = "NearIconBadge" -- client-side tag on each station badge found

local function isBadge(inst: Instance): boolean
	if not inst:IsA("BillboardGui") or inst.Name ~= BADGE then
		return false
	end
	local parent = inst.Parent
	return parent ~= nil and parent:IsA("BasePart") and parent:GetAttribute("StationId") ~= nil
end

function NearIcons.init(_ctx: Types.Ctx)
	local clinics = Workspace:WaitForChild("Clinics", 30)
	if not clinics then
		return
	end
	for _, inst in clinics:GetDescendants() do
		if isBadge(inst) then
			CollectionService:AddTag(inst, TAG)
		end
	end
	clinics.DescendantAdded:Connect(function(inst)
		-- the builders set the StationId attribute and the badge's name before it is parented
		if isBadge(inst) then
			CollectionService:AddTag(inst, TAG)
		end
	end)

	local hiddenByUs: { [BillboardGui]: boolean } = {}
	setmetatable(hiddenByUs :: any, { __mode = "k" })
	task.spawn(function()
		while true do
			task.wait(1 / Pure.CHECKS_PER_SECOND)
			local camera = Workspace.CurrentCamera
			if camera then
				local eye = camera.CFrame.Position
				for _, inst in CollectionService:GetTagged(TAG) do
					local gui = inst :: BillboardGui
					local part = gui.Parent
					if part and part:IsA("BasePart") then
						local at = part.Position + Vector3.new(0, gui.StudsOffset.Y, 0)
						local was = hiddenByUs[gui] == true
						local now = Pure.hidden((at - eye).Magnitude, was)
						if now and not was and gui.Enabled then
							gui.Enabled = false
							hiddenByUs[gui] = true
						elseif not now and was then
							hiddenByUs[gui] = nil
							gui.Enabled = true
						end
					end
				end
			end
		end
	end)
end

return NearIcons
