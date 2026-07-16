--!nonstrict
--[[
	OverviewPage — the Studio window's home page: is the engine synced, what content exists
	(click a row to jump to its editor), and where the docs live.
]]

local Theme = require(script.Parent.Theme)

local OverviewPage = {}

-- deps = { StatAdmin, ContentAdmin, selectPage(id) }
function OverviewPage.mount(container: Frame, deps: any): { refresh: () -> () }
	local header = Theme.header(container, "SurvivorCore Studio")
	local scroll = Theme.scroll(32, 0, 6)
	scroll.Parent = container

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end

		-- Engine status.
		local roster = deps.StatAdmin.readRoster()
		local status = Theme.panel()
		status.LayoutOrder = 1
		status.Parent = scroll
		Theme.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = "Engine",
			Font = Theme.FONT_BOLD,
			TextSize = 14,
			LayoutOrder = 0,
		}).Parent =
			status
		Theme.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = if roster.ok
				then `✓ Synced — {roster.source or "ReplicatedStorage.SurvivorCore"}. Stats, engine config and content editors are live.`
				else `✗ {roster.reason or "Engine not found in this place."}`,
			TextColor3 = if roster.ok then Theme.COLOR.DIM else Theme.COLOR.DANGER,
			TextWrapped = true,
			TextSize = 12,
			LayoutOrder = 1,
		}).Parent =
			status

		-- Content counts (click-through).
		local content = Theme.panel()
		content.LayoutOrder = 2
		content.Parent = scroll
		Theme.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = "Content",
			Font = Theme.FONT_BOLD,
			TextSize = 14,
			LayoutOrder = 0,
		}).Parent =
			content
		for i, catKey in deps.ContentAdmin.ORDER do
			local cat = deps.ContentAdmin.CATEGORIES[catKey]
			local count = #deps.ContentAdmin.listRoster(catKey)
			local row = Theme.make("TextButton", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = Theme.COLOR.PANEL,
				AutoButtonColor = false,
				Text = "",
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, { Theme.corner(4) }) :: TextButton
			row.Parent = content
			Theme.label({
				Size = UDim2.new(1, -40, 1, 0),
				Position = UDim2.fromOffset(6, 0),
				Text = cat.title,
				TextColor3 = Theme.COLOR.DIM,
				TextSize = 12,
			}).Parent =
				row
			local badge = Theme.badge(tostring(count), Theme.COLOR.TEXT)
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, -4, 0.5, 0)
			badge.Parent = row
			Theme.hover(row, Theme.COLOR.PANEL, Theme.COLOR.PANEL_HOVER)
			row.MouseButton1Click:Connect(function()
				deps.selectPage("content/" .. catKey)
			end)
		end

		-- Pointers.
		local help = Theme.panel()
		help.LayoutOrder = 3
		help.Parent = scroll
		Theme.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = "How it works",
			Font = Theme.FONT_BOLD,
			TextSize = 14,
			LayoutOrder = 0,
		}).Parent =
			help
		Theme.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "Everything here is no-code and deltas-only: a field is written ONLY when it"
				.. " differs from the engine default, so unset fields keep following engine updates."
				.. " Stats apply live; Engine Config and content edits apply on the next Play."
				.. " Docs: docs/admin-plugin.md in the SurvivorCore repo.",
			TextColor3 = Theme.COLOR.DIM,
			TextWrapped = true,
			TextSize = 12,
			LayoutOrder = 1,
		}).Parent =
			help
	end

	header.refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return OverviewPage
