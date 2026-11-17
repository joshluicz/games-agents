--!strict
-- SendCard: "Where should it go?" (simple-start design §2; memory-20261117-006: the player sends each patient to the
-- right place). Client only.
--   init(ctx)
--   SendCard.Pure   the card's rules as plain values (tests/Routing.spec loads the PURE block on its own)
--
-- A waiting patient carries a "Send" prompt (Server/Patients: SendPrompt, attributes VisitId and Choice). At Lv 1-2
-- there is one kind of place, so the press itself sends it on the server and nothing shows here. From Lv 3, with the
-- X-ray bay open, the prompt's Choice is true: this client opens a small card on the shared modal shell (a Popup:
-- the navy header, no look of its own) with two big Secondary buttons, "🩺 Exam bay" and "📸 X-ray" (Logic/Routing.TEXT;
-- the title is words only). The calm UI (UI direction §2, memory-20261117-007): each button carries ONE emoji, the
-- Art noun of the place it picks (rule 2's "🩺 Healer" case), in the Normal voice (R5); neither is filled, because
-- neither is "the" answer; no outline, no chip, nothing that loops. A tap fires the SendPatient RemoteEvent (visitId, "Exam" | "XRay") and closes the card.
-- The server checks everything and answers with a toast when it helps: a wrong pick is gently corrected ("That one
-- needs the X-ray!") and the patient stays seated, with no penalty; no free place says "All bays are busy!".
-- Walking away from the patient, or the patient going (sent by someone else, or home), closes the card.
-- Nothing runs every frame: the distance check runs only while the card is open.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Routing = require(Shared:WaitForChild("Logic"):WaitForChild("Routing"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local SendCard = {}

-- PURE-BEGIN
-- No Roblox types: tests/Routing.spec loads this block on its own, with Routing (Logic/Routing) in its environment.
local Pure = {}

Pure.PROMPT_NAME = "SendPrompt" -- Server/Patients' prompt on each waiting patient
Pure.REACH = 16 -- studs from the patient before the card closes by itself (the prompt reaches 8, the server 14)
Pure.BUTTON_HEIGHT = 64

-- The card's two buttons, in order: { Choice, Text }.
function Pure.buttons(): { { Choice: string, Text: string } }
	local out = {}
	for _, kind in Routing.KINDS do
		table.insert(out, { Choice = kind, Text = Routing.TEXT[kind] })
	end
	return out
end

-- The patient this press opens the card for: its VisitId, or nil when the press isn't a Send prompt's, isn't this
-- player's, or needs no card (one kind of place: the server sent it already).
function Pure.opens(promptName: any, mine: any, choice: any, visitId: any): number?
	if promptName ~= Pure.PROMPT_NAME or mine ~= true or choice ~= true then
		return nil
	end
	if type(visitId) ~= "number" or visitId ~= visitId or visitId % 1 ~= 0 then
		return nil
	end
	return visitId
end

-- The card stays open only while the patient still waits to be sent (its State "Waiting", no bay) and you stand by it.
function Pure.stays(state: any, bay: any, distance: any): boolean
	return state == "Waiting"
		and (bay == nil or bay == "")
		and type(distance) == "number"
		and distance == distance
		and distance <= Pure.REACH
end
-- PURE-END
SendCard.Pure = Pure

local player = Players.LocalPlayer

function SendCard.init(ctx: Types.Ctx)
	local modal = Hud.modal(ctx, {
		Name = "Send",
		Title = Routing.TEXT.Title,
		Layer = "Popup",
		MaxSize = Vector2.new(420, 300),
	})
	local body = Instance.new("Frame")
	body.Name = "Places"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	Kit.pad(body)
	Kit.list(body, Enum.FillDirection.Vertical, Theme.Space.Gap) -- centred both ways
	body.Parent = modal.Body

	local visitId: number? = nil
	local openToken = 0

	local function pick(choice: string)
		local id = visitId
		modal.close()
		if id then
			ctx.Remotes.SendPatient:FireServer(id, choice)
		end
	end

	local first: GuiObject? = nil
	for index, entry in Pure.buttons() do
		local button = Kit.button({
			Name = "Place_" .. entry.Choice,
			Kind = "Secondary",
			Text = entry.Text,
			Size = UDim2.new(1, 0, 0, Pure.BUTTON_HEIGHT),
			LayoutOrder = index,
			Parent = body,
		})
		Kit.voice(button, "Normal") -- a Secondary button speaks in the Normal voice (UI direction R5)
		first = first or button
		button.Activated:Connect(function()
			pick(entry.Choice)
		end)
	end

	local function open(patient: Model, id: number)
		visitId = id
		modal.Focus = first or modal.CloseButton
		modal.open()
		-- Walk away, or the patient goes (someone else sent it, it went home): the card closes by itself.
		openToken += 1
		local token = openToken
		task.spawn(function()
			while modal.isOpen() and openToken == token do
				task.wait(0.3)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local at = patient.PrimaryPart
				local distance = if patient.Parent
						and at
						and root
						and root:IsA("BasePart")
					then (root.Position - at.Position).Magnitude
					else math.huge
				if not Pure.stays(patient:GetAttribute("State"), patient:GetAttribute("Bay"), distance) then
					if openToken == token and modal.isOpen() then
						modal.close()
					end
					return
				end
			end
		end)
	end

	-- A Send prompt this player pressed (fires on this client only for the local player).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		local id = Pure.opens(prompt.Name, who == player, prompt:GetAttribute("Choice"), prompt:GetAttribute("VisitId"))
		local patient = prompt:FindFirstAncestorWhichIsA("Model")
		if id and patient then
			open(patient, id)
		end
	end)
end

return SendCard
