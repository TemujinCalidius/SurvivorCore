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
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local container = Instance.new("Frame")
	container.Name = "Bars"
	container.Position = UDim2.fromOffset(18, 18)
	container.Size = UDim2.fromOffset(220, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = screen

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
			label.Size = UDim2.fromScale(1, 1)
			label.Text = stat.name
			label.TextColor3 = Color3.fromRGB(245, 245, 245)
			label.TextSize = 12
			label.Font = Enum.Font.GothamMedium
			label.ZIndex = 2
			label.Parent = bar

			CollectionService:AddTag(bar, BAR_TAG)
			-- Parent last, fully built, so the binder sees Stat + Fill when it fires.
			bar.Parent = container
		end
	end

	return screen
end

return HudFallback
