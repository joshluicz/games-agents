--!strict
-- Toasts (build plan Task 6): short messages stacked at the top centre. Every toast in the game, from the
-- server or from ctx.toast, arrives on the client bus as "Toast" (Main.client wires that).
--   init(ctx)   listens to ctx.on("Toast", text)
-- The look is the old shop toast (cream card, ink text), with a pop in and a fade out. The same text twice in a
-- row bumps a "×2" counter instead of stacking a copy. At most MAX_SHOWN at once; the oldest goes first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Toasts = {}

local MAX_SHOWN = 3
local MAX_CHARS = 120
local BASE_SECONDS = 2.6
local SECONDS_PER_EXTRA_CHAR = 0.03 -- longer messages stay a little longer
local MAX_SECONDS = 5
local CREAM = Color3.fromRGB(255, 245, 200)
-- The HUD's wallet (top left) and clock (top right) are about this wide; toasts sit between them when they fit.
local SIDE_RESERVE = 214
local MIN_WIDTH = 240
local MAX_WIDTH = 440
local BELOW_WALLET_Y = 118

type Toast = {
	Text: string,
	Count: number,
	Group: CanvasGroup,
	Label: TextLabel,
	Scale: UIScale,
	Token: number,
	Leaving: boolean,
}

function Toasts.init(ctx: Types.Ctx)
	local gui = Kit.screen("Toasts", Theme.DisplayOrder.Toast)

	local holder = Instance.new("Frame")
	holder.Name = "Stack"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, Theme.Size.Margin)
	holder.Size = UDim2.fromOffset(MAX_WIDTH, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Kit.list(holder, Enum.FillDirection.Vertical, 6)
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Between the wallet and the clock when there's room; on narrow screens, full width under the wallet.
	local function fit()
		local width = gui.AbsoluteSize.X
		local between = width - SIDE_RESERVE * 2
		if between >= MIN_WIDTH then
			holder.Size = UDim2.fromOffset(math.min(MAX_WIDTH, between), 0)
			holder.Position = UDim2.new(0.5, 0, 0, Theme.Size.Margin)
		else
			holder.Size = UDim2.fromOffset(math.min(MAX_WIDTH, width - Theme.Size.Margin * 2), 0)
			holder.Position = UDim2.new(0.5, 0, 0, BELOW_WALLET_Y)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local shown: { Toast } = {}
	local order = 0

	local function remove(toast: Toast, quick: boolean)
		if toast.Leaving then
			return
		end
		toast.Leaving = true
		local index = table.find(shown, toast)
		if index then
			table.remove(shown, index)
		end
		if Hud.calm() or quick then
			toast.Group:Destroy()
			return
		end
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toast.Scale, info, { Scale = 0.9 }):Play()
		local fade = TweenService:Create(toast.Group, info, { GroupTransparency = 1 })
		fade.Completed:Once(function()
			toast.Group:Destroy()
		end)
		fade:Play()
	end

	local function schedule(toast: Toast)
		toast.Token += 1
		local token = toast.Token
		local extra = math.max(0, #toast.Text - 30) * SECONDS_PER_EXTRA_CHAR
		task.delay(math.min(MAX_SECONDS, BASE_SECONDS + extra), function()
			if toast.Token == token then
				remove(toast, false)
			end
		end)
	end

	local function popIn(toast: Toast, from: number)
		if Hud.calm() then
			toast.Scale.Scale = 1
			toast.Group.GroupTransparency = 0
			return
		end
		toast.Scale.Scale = from
		TweenService:Create(toast.Scale, Theme.Tween.PopIn, { Scale = 1 }):Play()
		TweenService:Create(toast.Group, Theme.Tween.Fade, { GroupTransparency = 0 }):Play()
	end

	local function show(text: any)
		if type(text) ~= "string" or text == "" then
			return
		end
		if #text > MAX_CHARS then
			text = string.sub(text, 1, MAX_CHARS) .. "…"
		end

		-- The same message again: count it on the newest toast instead of stacking a copy.
		local newest = shown[#shown]
		if newest and newest.Text == text and not newest.Leaving then
			newest.Count += 1
			newest.Label.Text = text .. "  ×" .. newest.Count
			popIn(newest, 1.08)
			schedule(newest)
			return
		end

		while #shown >= MAX_SHOWN do
			remove(shown[1], true)
		end

		order += 1
		local group = Instance.new("CanvasGroup")
		group.Name = "Toast"
		group.LayoutOrder = order
		group.Size = UDim2.fromScale(1, 0)
		group.AutomaticSize = Enum.AutomaticSize.Y
		group.BackgroundColor3 = CREAM
		group.BorderSizePixel = 0
		group.GroupTransparency = 1
		Kit.corner(group, Theme.Size.Corner)
		local stroke = Kit.stroke(group, Theme.Colors.Stroke, 2)
		stroke.Transparency = 0.35
		local pad = Kit.pad(group, 8)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)

		local label = Kit.label({
			Name = "Text",
			Text = text,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 22,
			TextWrapped = true,
			Parent = group,
		})

		local scale = Instance.new("UIScale")
		scale.Parent = group
		group.Parent = holder

		local toast: Toast = {
			Text = text,
			Count = 1,
			Group = group,
			Label = label,
			Scale = scale,
			Token = 0,
			Leaving = false,
		}
		table.insert(shown, toast)
		popIn(toast, 0.8)
		schedule(toast)
	end

	ctx.on("Toast", show)
end

return Toasts
