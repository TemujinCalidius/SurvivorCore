--!nonstrict
--[[
	AchievementsUi — the Achievements tab. CLIENT-ONLY.

	Fills the menu's scaffolded "achievements" tab with one row per registered achievement,
	rendered from the replicated defs (AchievementData) + the AchievementState Player attribute:
	icon (if any) + name + description + a progress bar toward the counter threshold; unlocked
	rows get a gold check. Re-renders whenever AchievementState changes. Themed from the "UI"
	Config section. Booted by SurvivorCore.startClient() (after PanelManager).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.AchievementsUi is client-only")

local AchievementData = require(script.Parent.Parent.shared.AchievementData)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local PanelManager = require(script.Parent.PanelManager)

local AchievementsUi = {}

local started = false
local localPlayer = Players.LocalPlayer

local GOLD = Color3.fromRGB(240, 190, 80)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildAchievements(content: Instance)
	local theme = UiConfig.get().Theme

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AchievementList"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Active = true -- sink clicks so the menu's click-outside overlay doesn't close the menu
	scroll.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local function addRow(def: any, unlocked: boolean, count: number, orderNum: number)
		local row = Instance.new("Frame")
		row.Name = "Achievement_" .. def.key
		row.Size = UDim2.new(1, -8, 0, 56)
		row.BackgroundColor3 = theme.SlotColor or theme.PanelColor or Color3.fromRGB(30, 34, 44)
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.LayoutOrder = orderNum
		row.Parent = scroll
		corner(row, theme.CornerRadius or 8)

		local hasIcon = typeof(def.icon) == "string" and def.icon ~= ""
		if hasIcon then
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(36, 36)
			icon.Position = UDim2.fromOffset(10, 10)
			icon.Image = def.icon
			icon.ImageTransparency = if unlocked then 0 else 0.35
			icon.Parent = row
		end
		local textX = if hasIcon then 56 else 12

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, -textX - 130, 0, 20)
		name.Position = UDim2.fromOffset(textX, 8)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Font = theme.FontBold or Enum.Font.GothamBold
		name.TextSize = 14
		name.TextColor3 = if unlocked then GOLD else (theme.Text or Color3.fromRGB(245, 245, 245))
		name.Text = if unlocked then "✓ " .. def.name else def.name
		name.Parent = row

		if def.description then
			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Size = UDim2.new(1, -textX - 130, 0, 16)
			desc.Position = UDim2.fromOffset(textX, 30)
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.Font = theme.Font or Enum.Font.Gotham
			desc.TextSize = 12
			desc.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
			desc.Text = def.description
			desc.Parent = row
		end

		-- Progress toward the threshold (a full gold bar once unlocked).
		local shown = math.min(count, def.threshold)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromOffset(110, 16)
		label.Position = UDim2.new(1, -122, 0, 10)
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.Font = theme.Font or Enum.Font.Gotham
		label.TextSize = 12
		label.TextColor3 = if unlocked then GOLD else (theme.TextSecondary or Color3.fromRGB(200, 205, 215))
		label.Text = `{shown}/{def.threshold}`
		label.Parent = row

		local track = Instance.new("Frame")
		track.Size = UDim2.fromOffset(110, 6)
		track.Position = UDim2.new(1, -122, 0, 32)
		track.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
		track.BorderSizePixel = 0
		track.Parent = row
		corner(track, 3)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(if unlocked then 1 else math.clamp(count / def.threshold, 0, 1), 1)
		fill.BackgroundColor3 = if unlocked then GOLD else (theme.Accent or Color3.fromRGB(120, 170, 255))
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 3)
	end

	local function render()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local defs = AchievementData.getAll()
		local state = AchievementData.decodeState(localPlayer)

		if #defs == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.Font = theme.Font or Enum.Font.Gotham
			empty.TextSize = 14
			empty.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
			empty.Text = "No achievements registered."
			empty.Parent = scroll
			return
		end

		-- Unlocked first (most satisfying up top), then by progress toward threshold.
		local sorted = table.clone(defs)
		table.sort(sorted, function(a, b)
			local ua, ub = state.u[a.key] == true, state.u[b.key] == true
			if ua ~= ub then
				return ua
			end
			local pa = (tonumber(state.c[a.counter]) or 0) / a.threshold
			local pb = (tonumber(state.c[b.counter]) or 0) / b.threshold
			if pa ~= pb then
				return pa > pb
			end
			return a.name < b.name
		end)

		for i, def in sorted do
			addRow(def, state.u[def.key] == true, tonumber(state.c[def.counter]) or 0, i)
		end
	end

	render()
	localPlayer:GetAttributeChangedSignal(AchievementData.STATE_ATTR):Connect(render)
end

function AchievementsUi.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	PanelManager.registerPanel({
		id = "achievements",
		title = "Achievements",
		order = 4,
		build = buildAchievements,
	})
end

return AchievementsUi
