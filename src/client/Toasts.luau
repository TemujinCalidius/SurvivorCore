--!nonstrict
--[[
	Toasts — client. Small top-right notifications ("Quest complete", "Achievement unlocked").

	The server fires the `Notify` RemoteEvent with { title, body?, icon?, kind? }; this queues and
	slides them in (at most QUEUE_MAX on screen; extras wait). Games can also call
	`Toasts.show(payload)` locally. Styled from the UI Config Theme like every other engine
	surface — dark translucent panel, accent title. Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

assert(RunService:IsClient(), "SurvivorCore.Toasts is client-only — boot it via SurvivorCore.startClient()")

local Remotes = require(script.Parent.Parent.shared.Remotes)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)

local Toasts = {}

local started = false
local player = Players.LocalPlayer

local QUEUE_MAX = 3 -- visible at once
local HOLD_SECONDS = 4
local TOAST_W, TOAST_H = 260, 56

local list: Frame? = nil
local pending: { any } = {}
local showing = 0

local function ensureGui(): Frame?
	if list and list.Parent then
		return list
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "SurvivorCoreToasts"
	g.ResetOnSpawn = false
	g.DisplayOrder = 80

	local holder = Instance.new("Frame")
	holder.Name = "List"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -12, 0, 12)
	holder.Size = UDim2.fromOffset(TOAST_W, (TOAST_H + 8) * QUEUE_MAX)
	holder.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = holder
	holder.Parent = g

	g.Parent = playerGui
	list = holder
	return holder
end

local function buildToast(payload: any): Frame
	local theme = UiConfig.get().Theme or {}
	local accent = if payload.kind == "achievement"
		then Color3.fromRGB(240, 190, 80) -- gold for achievements
		else (theme.Accent or Color3.fromRGB(120, 170, 255))

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
	frame.BackgroundColor3 = theme.PanelColor or Color3.fromRGB(20, 23, 30)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, tonumber(theme.CornerRadius) or 10)
	corner.Parent = frame

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 4, 1, -12)
	bar.Position = UDim2.fromOffset(6, 6)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = bar
	bar.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 22)
	title.Position = UDim2.fromOffset(18, 7)
	title.BackgroundTransparency = 1
	title.Text = tostring(payload.title or "")
	title.TextColor3 = accent
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = theme.FontBold or Enum.Font.GothamBold
	title.TextSize = 14
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -24, 0, 20)
	body.Position = UDim2.fromOffset(18, 28)
	body.BackgroundTransparency = 1
	body.Text = tostring(payload.body or "")
	body.TextColor3 = theme.Text or Color3.fromRGB(235, 238, 245)
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.Font = theme.Font or Enum.Font.GothamMedium
	body.TextSize = 13
	body.Parent = frame

	return frame
end

local function pump()
	if showing >= QUEUE_MAX or #pending == 0 then
		return
	end
	local holder = ensureGui()
	if not holder then
		return
	end
	local payload = table.remove(pending, 1)
	showing += 1

	local frame = buildToast(payload)
	frame.Position = UDim2.fromOffset(TOAST_W + 20, 0) -- slid off-right; UIListLayout owns Y
	frame.Parent = holder
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()

	task.delay(HOLD_SECONDS, function()
		local out = TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(TOAST_W + 20, 0),
		})
		out.Completed:Once(function()
			frame:Destroy()
			showing -= 1
			pump()
		end)
		out:Play()
	end)
end

-- Show a toast locally: { title, body?, icon?, kind? ("quest" | "achievement" | nil) }.
function Toasts.show(payload: any)
	if typeof(payload) ~= "table" or payload.title == nil then
		return
	end
	table.insert(pending, payload)
	pump()
end

function Toasts.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true
	Remotes.event("Notify").OnClientEvent:Connect(function(payload)
		Toasts.show(payload)
	end)
end

return Toasts
