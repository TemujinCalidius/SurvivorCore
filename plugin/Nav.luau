--!nonstrict
--[[
	Nav — the plugin's sidebar rail + page router. Pages are data (id/label/section/mount);
	Nav renders the grouped rail (uppercase section headers, count badges), lazy-mounts each
	page into its own detail frame on first selection, and toggles visibility after that —
	so per-page state (scroll position, footer status) survives switching.

	refreshAll() refreshes the ACTIVE page immediately and dirty-flags the other mounted pages,
	which re-render the next time they're shown — an edit on one page never rebuilds a form the
	user might be mid-thought on elsewhere, but every page is fresh by the time it's seen.
]]

local Theme = require(script.Parent.Theme)

local Nav = {}

export type PageHandle = { refresh: () -> () }

export type Page = {
	id: string,
	label: string,
	section: string, -- rail group header ("" = top-level, no header)
	badge: (() -> number?)?,
	hidden: boolean?, -- routable but not listed (e.g. search results)
	mount: (frame: Frame) -> PageHandle,
}

export type Options = {
	railWidth: number?,
	initialId: string?,
	onNavigate: ((id: string) -> ())?,
	onSearch: ((query: string) -> ())?,
}

local ITEM_H = 24
local SEARCH_H = 26

function Nav.mount(root: Frame, pages: { Page }, opts: Options?)
	local options: Options = opts or {}
	local railWidth = options.railWidth or 156

	local byId: { [string]: Page } = {}
	for _, page in pages do
		byId[page.id] = page
	end

	-- ── Layout: rail (left) + detail (right) ────────────────────────────────
	local rail = Theme.make("Frame", {
		Size = UDim2.new(0, railWidth, 1, 0),
		BackgroundColor3 = Theme.COLOR.RAIL,
		BorderSizePixel = 0,
	}) :: Frame
	rail.Parent = root

	local detail = Theme.make("Frame", {
		Position = UDim2.fromOffset(railWidth, 0),
		Size = UDim2.new(1, -railWidth, 1, 0),
		BackgroundTransparency = 1,
	}) :: Frame
	detail.Parent = root

	-- Search box pinned to the rail top.
	local searchBox = Theme.textBox({
		Size = UDim2.new(1, -12, 0, SEARCH_H),
		Position = UDim2.fromOffset(6, 6),
		Text = "",
		PlaceholderText = "Search content…",
		TextSize = 12,
	})
	searchBox.Parent = rail
	if options.onSearch then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			options.onSearch(searchBox.Text)
		end)
	end

	local railScroll = Theme.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, SEARCH_H + 12),
		Size = UDim2.new(1, 0, 1, -(SEARCH_H + 12)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		Theme.make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		Theme.pad(6, 6, 0, 10),
	}) :: ScrollingFrame
	railScroll.Parent = rail

	-- ── Router state ─────────────────────────────────────────────────────────
	local frames: { [string]: Frame } = {}
	local handles: { [string]: PageHandle } = {}
	local dirty: { [string]: boolean } = {}
	local activeId: string? = nil
	local items: { [string]: { button: TextButton, label: TextLabel, bar: Frame, badge: TextLabel? } } = {}

	local function paintItem(id: string)
		local item = items[id]
		if not item then
			return
		end
		local selected = id == activeId
		item.button.BackgroundColor3 = if selected then Theme.COLOR.PANEL else Theme.COLOR.RAIL
		item.button.BackgroundTransparency = if selected then 0 else 1
		item.label.TextColor3 = if selected then Theme.COLOR.TEXT else Theme.COLOR.DIM
		item.bar.Visible = selected
	end

	local function refreshBadges()
		for id, item in items do
			local page = byId[id]
			if item.badge and page and page.badge then
				local count = page.badge()
				item.badge.Text = if count ~= nil then tostring(count) else ""
				item.badge.Visible = count ~= nil
			end
		end
	end

	local api = {}

	function api.selectPage(id: string)
		local page = byId[id]
		if not page then
			return
		end
		if not frames[id] then
			local frame = Theme.make("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.COLOR.BG,
				BorderSizePixel = 0,
				Visible = false,
			}) :: Frame
			frame.Parent = detail
			frames[id] = frame
			handles[id] = page.mount(frame)
			dirty[id] = nil -- mount() renders fresh
		end
		if activeId ~= id then
			local previous = activeId and frames[activeId :: string]
			if previous then
				previous.Visible = false
			end
			local old = activeId
			activeId = id
			frames[id].Visible = true
			if old then
				paintItem(old)
			end
			paintItem(id)
		end
		if dirty[id] then
			dirty[id] = nil
			handles[id].refresh()
		end
		if options.onNavigate and not page.hidden then
			options.onNavigate(id)
		end
	end

	-- Refresh the active page now; mark every other mounted page to refresh on next show.
	function api.refreshAll()
		for id in handles do
			if id == activeId then
				handles[id].refresh()
			else
				dirty[id] = true
			end
		end
		refreshBadges()
	end

	function api.getActiveId(): string?
		return activeId
	end

	-- ── Rail rendering (grouped, ordered as given) ───────────────────────────
	local order = 0
	local seenSections: { [string]: boolean } = {}
	for _, page in pages do
		if page.hidden then
			continue
		end
		if page.section ~= "" and not seenSections[page.section] then
			seenSections[page.section] = true
			order += 1
			Theme.label({
				Size = UDim2.new(1, 0, 0, 20),
				Text = string.upper(page.section),
				TextColor3 = Theme.COLOR.DIM,
				TextSize = 10,
				LayoutOrder = order,
			}).Parent =
				railScroll
		end
		order += 1

		local button = Theme.make("TextButton", {
			Size = UDim2.new(1, 0, 0, ITEM_H),
			BackgroundColor3 = Theme.COLOR.RAIL,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, { Theme.corner(4) }) :: TextButton
		button.Parent = railScroll
		local label = Theme.make("TextLabel", {
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			Text = page.label,
			TextColor3 = Theme.COLOR.DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 12,
			Font = Theme.FONT,
		}) :: TextLabel
		label.Parent = button

		local bar = Theme.make("Frame", {
			Size = UDim2.new(0, 2, 1, -6),
			Position = UDim2.fromOffset(0, 3),
			BackgroundColor3 = Theme.COLOR.ACCENT,
			BorderSizePixel = 0,
			Visible = false,
		}) :: Frame
		bar.Parent = button

		local badgeLabel: TextLabel? = nil
		if page.badge then
			badgeLabel = Theme.badge("")
			local badge = badgeLabel :: TextLabel
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, -4, 0.5, 0)
			badge.Parent = button
		end

		items[page.id] = { button = button, label = label, bar = bar, badge = badgeLabel }
		button.MouseEnter:Connect(function()
			if page.id ~= activeId then
				button.BackgroundTransparency = 0
				button.BackgroundColor3 = Theme.COLOR.PANEL_HOVER
			end
		end)
		button.MouseLeave:Connect(function()
			paintItem(page.id)
		end)
		button.MouseButton1Click:Connect(function()
			api.selectPage(page.id)
		end)
	end

	refreshBadges()
	api.selectPage(options.initialId or pages[1].id)

	return api
end

return Nav
