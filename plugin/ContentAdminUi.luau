--!nonstrict
--[[
	ContentAdminUi — the no-code content editor pages. One sidebar page per category
	(mountCategory), each rendering the MERGED roster (issue #40):

	  • authored entries — Configurations under SurvivorCoreContent/<folder>: the full editor
	    (every field seeded, Delete destroys the def), exactly as before.
	  • override entries — Configurations under SurvivorCoreContent/Overrides/<folder>: DELTAS
	    over a def registered from code. Blank = inherit the code value (the plugin can't show
	    code defaults in Edit mode — registries fill at runtime); Remove restores the pristine
	    code def on the next Play.

	buildRosterEntry/matchEntry are exported so the global search page renders the same editable
	panels. All writes route through the `actions` table of record()-wrapped callbacks the plugin
	main supplies. Styling comes from Theme.
]]

local Theme = require(script.Parent.Theme)

local ContentAdminUi = {}

local ROW_H = Theme.ROW_H

-- A single authored-field row: label .... TextBox (committed on focus loss).
local function buildField(catKey: string, id: string, field: any, value: any, actions): Instance
	local row = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 })
	Theme.label({
		Size = UDim2.fromScale(0.4, 1),
		Text = field.label,
		TextColor3 = Theme.COLOR.DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		row
	local box = Theme.textBox({
		Size = UDim2.new(0.6, -4, 0, ROW_H - 4),
		Position = UDim2.new(0.4, 4, 0, 2),
		Text = tostring(value),
		PlaceholderText = field.placeholder or tostring(field.default),
	})
	box.Parent = row
	box.FocusLost:Connect(function()
		actions.set(catKey, id, field, box.Text)
	end)
	return row
end

-- A single override-field row: blank = inherit. Booleans cycle (inherit) → true → false.
local function buildOverrideField(catKey: string, id: string, field: any, state: any, actions): Instance
	local row = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 })
	Theme.label({
		Size = UDim2.fromScale(0.4, 1),
		Text = field.label,
		TextColor3 = if state.hasOverride then Theme.COLOR.TEXT else Theme.COLOR.DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		row

	if field.kind == "boolean" then
		local control = Theme.button({
			Size = UDim2.new(0.6, -4, 0, ROW_H - 4),
			Position = UDim2.new(0.4, 4, 0, 2),
			Text = if state.hasOverride then tostring(state.value) else "(inherit)",
			TextColor3 = if state.hasOverride then Theme.COLOR.TEXT else Theme.COLOR.DIM,
			TextSize = 13,
		})
		control.Parent = row
		control.MouseButton1Click:Connect(function()
			-- (inherit) → true → false → (inherit)
			local nextRaw: any
			if not state.hasOverride then
				nextRaw = true
			elseif state.value == true then
				nextRaw = false
			else
				nextRaw = "" -- blank = remove the attribute = inherit
			end
			actions.setOverride(catKey, id, field, nextRaw)
		end)
	else
		local box = Theme.textBox({
			Size = UDim2.new(0.6, -4, 0, ROW_H - 4),
			Position = UDim2.new(0.4, 4, 0, 2),
			Text = if state.hasOverride then tostring(state.value) else "",
			PlaceholderText = "(code default)",
		})
		box.Parent = row
		box.FocusLost:Connect(function()
			actions.setOverride(catKey, id, field, box.Text)
		end)
	end
	return row
end

-- One roster entry panel — branches authored vs override.
function ContentAdminUi.buildRosterEntry(catKey: string, entry: any, ContentAdmin: any, actions): Instance
	local cat = ContentAdmin.CATEGORIES[catKey]
	local panel = Theme.panel()
	local title = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 0 })
	title.Parent = panel

	local del = Theme.button({
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.new(1, -56, 0.5, -10),
		Text = if entry.override then "Remove" else "Delete",
		TextColor3 = Theme.COLOR.DANGER,
	})
	del.Parent = title
	del.MouseButton1Click:Connect(function()
		if entry.override then
			actions.deleteOverride(catKey, entry.id)
		else
			actions.delete(catKey, entry.id)
		end
	end)

	local labelRight = 64

	if entry.override then
		-- Accent pill marking this as a delta over a code-registered def.
		local pill = Theme.badge("override", Theme.COLOR.ACCENT)
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.new(1, -64, 0.5, 0)
		pill.Parent = title
		labelRight = 128
	elseif
		(catKey == "Resources" or catKey == "Mobs" or catKey == "Weapons" or catKey == "Quests") and actions.spawn
	then
		-- Gatherables + Mobs + Quests drop a tagged, def-linked instance; Weapons drop a starter
		-- Tool you can model the look on — all in front of the camera.
		local add = Theme.button({
			Size = UDim2.fromOffset(104, 20),
			Position = UDim2.new(1, -168, 0.5, -10),
			Text = if catKey == "Weapons"
				then "+ Tool model"
				elseif catKey == "Quests" then "+ Quest giver"
				else "+ Add to World",
			TextColor3 = Theme.COLOR.ACCENT,
			TextSize = 11,
		})
		add.Parent = title
		add.MouseButton1Click:Connect(function()
			actions.spawn(catKey, entry.id)
		end)
		labelRight = 176
	end

	Theme.label({
		Size = UDim2.new(1, -labelRight, 1, 0),
		Text = entry.id,
		TextSize = 14,
		Font = Theme.FONT_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		title

	for i, field in cat.fields do
		local row: any
		if entry.override then
			local state = ContentAdmin.readOverrideField(catKey, entry.id, field)
			row = buildOverrideField(catKey, entry.id, field, state, actions)
		else
			row = buildField(catKey, entry.id, field, ContentAdmin.read(catKey, entry.id, field), actions)
		end
		row.LayoutOrder = i
		row.Parent = panel
	end

	return panel
end

-- Case-insensitive substring match on the entry id and its `name` attribute (when the category
-- has one). Shared by the category pages and the global search page.
function ContentAdminUi.matchEntry(ContentAdmin: any, catKey: string, entry: any, loweredQuery: string): boolean
	if string.find(string.lower(entry.id), loweredQuery, 1, true) then
		return true
	end
	local node = if entry.override
		then ContentAdmin.getOverrideNode(catKey, entry.id)
		else ContentAdmin.getNode(catKey, entry.id)
	local name = node and node:GetAttribute("name")
	if typeof(name) == "string" and string.find(string.lower(name), loweredQuery, 1, true) then
		return true
	end
	return false
end

-- Mount one category's page. `actions` = { set, create, delete, spawn, createOverride,
-- setOverride, deleteOverride } — all record()-wrapped by the plugin main.
function ContentAdminUi.mountCategory(
	container: Frame,
	catKey: string,
	ContentAdmin: any,
	actions
): { refresh: () -> () }
	local cat = ContentAdmin.CATEGORIES[catKey]
	local header = Theme.header(container, cat.title)
	local scroll = Theme.scroll(32, 0, 8)
	scroll.Parent = container

	-- A failed Create/Override's reason, rendered by refresh() under the create row (the row
	-- itself is destroyed and rebuilt by record()'s refresh, so the message must live here).
	local lastError: string? = nil

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end

		-- Create row: [ new id ............ ] [ + Create ] [ + Override ]
		local createRow =
			Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1 })
		createRow.Parent = scroll
		local idBox = Theme.textBox({
			Size = UDim2.new(1, -172, 1, 0),
			Text = "",
			PlaceholderText = cat.keyLabel,
		})
		idBox.Parent = createRow
		local createBtn = Theme.button({
			Size = UDim2.fromOffset(76, 28),
			Position = UDim2.new(1, -164, 0, 0),
			Text = "+ Create",
			TextSize = 13,
		})
		createBtn.Parent = createRow
		createBtn.MouseButton1Click:Connect(function()
			local res = actions.create(catKey, idBox.Text)
			lastError = if typeof(res) == "table" and res.ok == false then res.message else nil
			refresh()
		end)
		local overrideBtn = Theme.button({
			Size = UDim2.fromOffset(84, 28),
			Position = UDim2.new(1, -84, 0, 0),
			Text = "+ Override",
			TextColor3 = Theme.COLOR.ACCENT,
			TextSize = 13,
		})
		overrideBtn.Parent = createRow
		overrideBtn.MouseButton1Click:Connect(function()
			local res = actions.createOverride(catKey, idBox.Text)
			lastError = if typeof(res) == "table" and res.ok == false then res.message else nil
			refresh()
		end)

		if lastError then
			local message = lastError :: string
			lastError = nil -- shown once; the next refresh clears it
			Theme.label({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = `✗ {message}`,
				TextColor3 = Theme.COLOR.DANGER,
				TextWrapped = true,
				TextSize = 12,
				LayoutOrder = 2,
			}).Parent =
				scroll
		end

		Theme.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "Create authors a full def here. Override tunes a def registered from code"
				.. " (invisible in Edit — registries fill at runtime): type its id, set ONLY the"
				.. " fields to change, blank = inherit. Typos warn in Output on Play.",
			TextColor3 = Theme.COLOR.DIM,
			TextWrapped = true,
			TextSize = 11,
			LayoutOrder = 3,
		}).Parent =
			scroll

		local roster = ContentAdmin.listRoster(catKey)
		if #roster == 0 then
			Theme.label({
				Size = UDim2.new(1, 0, 0, 22),
				Text = `No {string.lower(cat.title)} yet — create one above.`,
				TextColor3 = Theme.COLOR.DIM,
				TextSize = 12,
				LayoutOrder = 4,
			}).Parent =
				scroll
		else
			for i, entry in roster do
				local panel = ContentAdminUi.buildRosterEntry(catKey, entry, ContentAdmin, actions)
				panel.LayoutOrder = 4 + i
				panel.Parent = scroll
			end
		end
	end

	header.refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return ContentAdminUi
