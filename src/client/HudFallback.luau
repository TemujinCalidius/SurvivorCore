--[[
	HudFallback — the zero-setup safety net. CLIENT-ONLY.

	If no designer-authored HUD reaches the player (no template mounted, none
	bundled, none installed), the client binder calls this to build a deliberately
	minimal, unstyled bar stack so the HUD ALWAYS appears. It is intentionally plain
	— the authored `SurvivalHud` template is the real thing. Uses zero asset IDs.

	The bars it creates follow the same `SurvivorStatBar` tag + `Fill` child contract
	as the template, so the binder drives them identically.
]]

local CollectionService = game:GetService("CollectionService")

local BAR_TAG = "SurvivorStatBar"
local HUD_NAME = "SurvivalHud"

-- Plain, readable colors for the fallback only (the template carries its own art).
local FALLBACK_COLORS = {
	Health = Color3.fromRGB(232, 70, 70),
	Energy = Color3.fromRGB(90, 205, 120),
	Hunger = Color3.fromRGB(220, 140, 40),
	Thirst = Color3.fromRGB(60, 160, 230),
	Fatigue = Color3.fromRGB(160, 100, 220),
	Blood = Color3.fromRGB(180, 40, 40),
	Poison = Color3.fromRGB(120, 180, 60),
}

local HudFallback = {}

function HudFallback.build(playerGui: Instance, stats: { any })
	local screen = Instance.new("ScreenGui")
	screen.Name = HUD_NAME
	screen.ResetOnSpawn = false
	-- Respect the ~36px Roblox topbar inset so bars never render under the CoreGui menu.
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- A dark translucent background panel so the fallback reads cleanly, matching the
	-- authored template's look. Auto-sizes to its bars; the owner never edits this file.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.fromOffset(16, 12)
	panel.Size = UDim2.fromOffset(248, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(210, 220, 245)
	stroke.Thickness = 1
	stroke.Transparency = 0.85
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local container = Instance.new("Frame")
	container.Name = "Bars"
	container.Size = UDim2.fromScale(1, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	-- Parent the ScreenGui BEFORE tagging bars, so the tag-added signal fires while
	-- each bar is already a descendant of PlayerGui (the binder requires that).
	screen.Parent = playerGui

	local order = 0
	for _, stat in stats do
		if stat.display then
			order += 1

			local bar = Instance.new("Frame")
			bar.Name = stat.name
			bar.LayoutOrder = order
			bar.Size = UDim2.new(1, 0, 0, 18)
			bar.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
			bar.BorderSizePixel = 0
			bar:SetAttribute("Stat", stat.name)

			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Size = UDim2.fromScale(1, 1) -- driven by the binder
			fill.BackgroundColor3 = FALLBACK_COLORS[stat.name] or Color3.fromRGB(150, 150, 150)
			fill.BorderSizePixel = 0
			fill.Parent = bar

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -64, 1, 0)
			label.Position = UDim2.fromOffset(8, 0)
			label.Text = stat.name
			label.TextColor3 = Color3.fromRGB(245, 245, 245)
			label.TextSize = 12
			label.Font = Enum.Font.GothamMedium
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.ZIndex = 2
			label.Parent = bar

			-- Empty `Value` label the binder fills with the formatted number (optional but
			-- cheap; keeps the fallback consistent with the authored template).
			local valueLabel = Instance.new("TextLabel")
			valueLabel.Name = "Value"
			valueLabel.BackgroundTransparency = 1
			valueLabel.Size = UDim2.new(0, 52, 1, 0)
			valueLabel.Position = UDim2.new(1, -58, 0, 0)
			valueLabel.Text = ""
			valueLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
			valueLabel.TextSize = 12
			valueLabel.Font = Enum.Font.GothamMedium
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right
			valueLabel.ZIndex = 2
			valueLabel.Parent = bar

			CollectionService:AddTag(bar, BAR_TAG)
			-- Parent last, fully built, so the binder sees Stat + Fill when it fires.
			bar.Parent = container
		end
	end

	return screen
end

return HudFallback
