--!nonstrict
--[[
	SearchPage — global content search results. A hidden (rail-less) page the plugin main routes
	to while the rail search box has text. Matches ids + `name` attributes across every category
	(ContentAdminUi.matchEntry) and renders full EDITABLE entry panels grouped by category — you
	fix the thing right where you found it.
]]

local Theme = require(script.Parent.Theme)

local MAX_RESULTS = 50

local SearchPage = {}

-- deps = { ContentAdmin, ContentAdminUi, getQuery(), actions }
function SearchPage.mount(container: Frame, deps: any): { refresh: () -> () }
	local header = Theme.header(container, "Search")
	local scroll = Theme.scroll(32, 0, 8)
	scroll.Parent = container

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end

		local query = tostring(deps.getQuery() or "")
		if string.match(query, "^%s*$") then
			Theme.label({
				Size = UDim2.new(1, 0, 0, 40),
				Text = "Type in the sidebar box to search content by id or name.",
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
			}).Parent =
				scroll
			return
		end
		local lowered = string.lower(query)

		local order = 0
		local shown = 0
		local total = 0
		for _, catKey in deps.ContentAdmin.ORDER do
			local cat = deps.ContentAdmin.CATEGORIES[catKey]
			local matches = {}
			for _, entry in deps.ContentAdmin.listRoster(catKey) do
				if deps.ContentAdminUi.matchEntry(deps.ContentAdmin, catKey, entry, lowered) then
					table.insert(matches, entry)
				end
			end
			total += #matches
			if #matches == 0 then
				continue
			end
			order += 1
			Theme.label({
				Size = UDim2.new(1, 0, 0, 20),
				Text = `{cat.title} — {#matches} match{if #matches == 1 then "" else "es"}`,
				TextColor3 = Theme.COLOR.ACCENT,
				TextSize = 13,
				Font = Theme.FONT_BOLD,
				LayoutOrder = order,
			}).Parent =
				scroll
			for _, entry in matches do
				if shown >= MAX_RESULTS then
					break
				end
				shown += 1
				order += 1
				local panel = deps.ContentAdminUi.buildRosterEntry(catKey, entry, deps.ContentAdmin, deps.actions)
				panel.LayoutOrder = order
				panel.Parent = scroll
			end
		end

		if total == 0 then
			Theme.label({
				Size = UDim2.new(1, 0, 0, 40),
				Text = `No content matches '{query}'.`,
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
			}).Parent =
				scroll
		elseif total > shown then
			order += 1
			Theme.label({
				Size = UDim2.new(1, 0, 0, 22),
				Text = `Showing {shown} of {total} — refine your search.`,
				TextColor3 = Theme.COLOR.DIM,
				TextSize = 12,
				LayoutOrder = order,
			}).Parent =
				scroll
		end
	end

	header.refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return SearchPage
