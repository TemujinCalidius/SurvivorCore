--!nonstrict
--[[
	BuildAdminUi — the Build page (issue #11). Select a Part or Model in Studio and this asks
	"what is this object?", then renders that component's setup form from the engine's own schema.

	States: engine missing · nothing selected · ineligible class · untagged (the chooser) · tagged
	(identity card + form) · unknown tag · multi-select (apply to all). Every write goes through the
	plugin main's record() wrapper, so each edit is one undo step.

	Adding a component to the engine gives it a page here for free — there is no per-component UI
	code.
]]

local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local FieldRow = require(script.Parent.FieldRow)

local BuildAdminUi = {}

local FOOTER_H = 36

-- Group the schema's attributes by their `group`, preserving first-appearance order.
local function groupAttributes(specs: { any }, includeAdvanced: boolean): ({ string }, { [string]: { any } })
	local order, byGroup = {}, {}
	for _, spec in specs do
		if spec.advanced and not includeAdvanced then
			continue
		end
		local name = spec.group or "Settings"
		if not byGroup[name] then
			byGroup[name] = {}
			table.insert(order, name)
		end
		table.insert(byGroup[name], spec)
	end
	return order, byGroup
end

local function countAdvanced(specs: { any }): number
	local n = 0
	for _, spec in specs do
		if spec.advanced then
			n += 1
		end
	end
	return n
end

-- One clickable "what is this?" card. Ineligible components render dim and inert, with the reason.
-- The CARD ITSELF is the button when it's pickable: a full-size button parented INTO a panel would
-- be laid out by the panel's UIListLayout as another row (no opt-out; ZIndex doesn't affect
-- layout), leaving the card body dead and the button spilling onto the next card.
local function chooserCard(schema: any, display: any, eligible: boolean, reason: string?, onPick): GuiObject
	local panel: any = if eligible then Theme.panelButton() else Theme.panel()
	local title = Theme.label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = display.title,
		Font = Theme.FONT_BOLD,
		TextSize = 14,
		TextColor3 = if eligible then Theme.COLOR.TEXT else Theme.COLOR.DIM,
		LayoutOrder = 0,
	})
	title.Parent = panel

	local summary = if eligible then display.summary else `{display.summary}  —  {reason or "not eligible"}`
	Theme.label({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = summary,
		TextColor3 = Theme.COLOR.DIM,
		TextWrapped = true,
		TextSize = 12,
		LayoutOrder = 1,
	}).Parent =
		panel

	if eligible then
		(panel :: TextButton).MouseButton1Click:Connect(function()
			onPick(schema)
		end)
		Theme.hover(panel, Theme.COLOR.PANEL, Theme.COLOR.PANEL_HOVER)
	end
	return panel
end

-- actions = { applyType, clear, setField, resetField } — all record()-wrapped by the plugin main.
function BuildAdminUi.mount(container: Frame, BuildAdmin: any, ContentAdmin: any, actions: any): { refresh: () -> () }
	local header = Theme.header(container, "Build")
	local scroll = Theme.scroll(32, FOOTER_H, 8)
	scroll.Parent = container

	local footer = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		Position = UDim2.new(0, 0, 1, -FOOTER_H),
		BackgroundColor3 = Theme.COLOR.PANEL,
		BorderSizePixel = 0,
	}) :: Frame
	footer.Parent = container
	local status = Theme.label({
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Text = "",
		TextColor3 = Theme.COLOR.DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 11,
	})
	status.Parent = footer

	local chooserOpen = false -- "Change type" was clicked on an already-tagged instance
	local showAdvanced = false
	local refresh -- forward declaration (handlers below call it)

	local function say(text: string)
		status.Text = text
	end

	local function clearScroll()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end
	end

	local function note(text: string, order: number, color: Color3?)
		Theme.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = text,
			TextColor3 = color or Theme.COLOR.DIM,
			TextWrapped = true,
			TextSize = 12,
			LayoutOrder = order,
		}).Parent =
			scroll
	end

	-- ── writes ────────────────────────────────────────────────────────────────
	local function applyType(instances: { Instance }, schema: any, all: { any })
		local res = actions.applyType(instances, schema, all)
		chooserOpen = false
		refresh()
		if typeof(res) == "table" then
			local title = BuildAdmin.displayOf(schema).title
			local msg = `✓ {res.applied} object(s) → {title}`
			if (res.cleared or 0) > 0 then
				msg ..= `, cleared {res.cleared} old component(s)`
			end
			if (res.skipped or 0) > 0 then
				msg ..= `, skipped {res.skipped} ineligible`
			end
			say(msg)
		end
	end

	local function clearType(instances: { Instance }, all: { any }, extraTags: { string }?)
		local res = actions.clear(instances, all, extraTags)
		chooserOpen = false
		refresh()
		if typeof(res) == "table" then
			local n = res.cleared or 0
			say(if n > 0 then `✓ cleared {n} object(s)` else "nothing to clear on that object")
		end
	end

	local function commitField(instance: Instance, spec: any, raw: any)
		local res = actions.setField(instance, spec, raw)
		refresh()
		if typeof(res) == "table" and res.ok == false and res.error then
			say(`✗ {spec.label}: {res.error}`)
		end
	end

	-- ── the form for one tagged instance ──────────────────────────────────────
	local function buildForm(instance: Instance, schema: any, startOrder: number): number
		local order = startOrder
		local specs = schema.attributes or {}
		local groups, byGroup = groupAttributes(specs, showAdvanced)

		for _, groupName in groups do
			order += 1
			local panel = Theme.panel()
			panel.LayoutOrder = order
			panel.Parent = scroll

			Theme.label({
				Size = UDim2.new(1, 0, 0, 20),
				Text = groupName,
				Font = Theme.FONT_BOLD,
				TextSize = 13,
				LayoutOrder = 0,
			}).Parent =
				panel

			for i, spec in byGroup[groupName] do
				local state = BuildAdmin.readField(instance, spec)
				local choices = nil
				if spec.ref and ContentAdmin and ContentAdmin.listRoster then
					local ok, roster = pcall(ContentAdmin.listRoster, spec.ref)
					if ok and typeof(roster) == "table" then
						choices = {}
						for _, entry in roster do
							table.insert(choices, entry.id)
						end
					end
				end
				local row = FieldRow.build({
					spec = spec,
					state = state,
					choices = choices,
					onCommit = function(raw)
						commitField(instance, spec, raw)
					end,
					onReset = function()
						actions.resetField(instance, spec)
						refresh()
					end,
				})
				row.LayoutOrder = i
				row.Parent = panel

				-- First-run dead end: a field that points at authored content is useless until some
				-- exists, and the picker simply isn't there to hint at it. Say where to go, and
				-- offer to take them.
				if spec.ref and (not choices or #choices == 0) then
					local cat = ContentAdmin.CATEGORIES and ContentAdmin.CATEGORIES[spec.ref]
					local catTitle = (cat and cat.title) or spec.ref
					local jump = Theme.button({
						Size = UDim2.new(1, 0, 0, 22),
						Text = `No {catTitle} yet — create one →`,
						TextColor3 = Theme.COLOR.ACCENT,
						TextSize = 11,
						LayoutOrder = i,
					})
					jump.Parent = panel
					jump.MouseButton1Click:Connect(function()
						if actions.selectPage then
							actions.selectPage("content/" .. spec.ref)
						end
					end)
				end
			end
		end

		local advanced = countAdvanced(specs)
		if advanced > 0 then
			order += 1
			local toggle = Theme.button({
				Size = UDim2.new(1, 0, 0, 24),
				Text = if showAdvanced then "Hide advanced" else `Show advanced ({advanced})`,
				TextSize = 12,
				LayoutOrder = order,
			})
			toggle.Parent = scroll
			toggle.MouseButton1Click:Connect(function()
				showAdvanced = not showAdvanced
				refresh()
			end)
		end
		return order
	end

	-- ── render ────────────────────────────────────────────────────────────────
	refresh = function()
		clearScroll()

		local schemaRead = BuildAdmin.readSchema()
		if not schemaRead.ok then
			say("")
			note(schemaRead.reason or "Engine not found.", 1)
			return
		end
		local all = schemaRead.components

		local sel = BuildAdmin.getSelection()

		-- Nothing selected: explain, and list what this engine can build.
		if sel.count == 0 then
			say("")
			note("Select a Part or Model in the viewport or Explorer to set it up.", 1)
			local order = 1
			for _, schema in all do
				order += 1
				local display = BuildAdmin.displayOf(schema)
				local panel = Theme.panel()
				panel.LayoutOrder = order
				panel.Parent = scroll
				Theme.label({
					Size = UDim2.new(1, 0, 0, 18),
					Text = display.title,
					Font = Theme.FONT_BOLD,
					TextSize = 13,
					LayoutOrder = 0,
				}).Parent =
					panel
				Theme.label({
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = display.summary,
					TextColor3 = Theme.COLOR.DIM,
					TextWrapped = true,
					TextSize = 12,
					LayoutOrder = 1,
				}).Parent =
					panel
			end
			note("Tip: Content › Gatherables › “+ Add to World” drops a ready-made one.", order + 1)
			return
		end

		-- Multi-selection: apply/clear in bulk, no per-attribute form.
		if sel.count > 1 then
			say(`{#sel.eligible} of {sel.count} selected can take a component`)
			note(`{sel.count} objects selected ({#sel.eligible} eligible). Applying affects all of them.`, 1)
			local order = 1
			for _, schema in all do
				order += 1
				local display = BuildAdmin.displayOf(schema)
				local btn = Theme.button({
					Size = UDim2.new(1, 0, 0, 26),
					Text = `Apply to all — {display.title}`,
					TextSize = 13,
					LayoutOrder = order,
				})
				btn.Parent = scroll
				btn.MouseButton1Click:Connect(function()
					applyType(sel.eligible, schema, all)
				end)
			end
			order += 1
			local clearBtn = Theme.button({
				Size = UDim2.new(1, 0, 0, 26),
				Text = "Clear all",
				TextColor3 = Theme.COLOR.DANGER,
				TextSize = 13,
				LayoutOrder = order,
			})
			clearBtn.Parent = scroll
			clearBtn.MouseButton1Click:Connect(function()
				clearType(sel.eligible, all)
			end)
			return
		end

		-- Exactly one selected.
		local instance = sel.instances[1]
		if BuildAdmin.classify(instance) == "other" then
			say("")
			note(`Selected a {instance.ClassName} — Build works on Parts and Models.`, 1)
			return
		end

		local id = BuildAdmin.identify(instance, schemaRead)
		local order = 0

		if id.stale then
			order += 1
			note(
				"⚠ This object carries a leftover runtime bind marker (copied out of a Play session)."
					.. " Applying or clearing below removes it.",
				order,
				Theme.COLOR.DANGER
			)
		end

		if id.schema and not chooserOpen then
			local display = BuildAdmin.displayOf(id.schema)

			-- Identity card + change/clear.
			order += 1
			local card = Theme.panel()
			card.LayoutOrder = order
			card.Parent = scroll
			Theme.label({
				Size = UDim2.new(1, 0, 0, 20),
				Text = `This is a {display.title}`,
				Font = Theme.FONT_BOLD,
				TextSize = 14,
				LayoutOrder = 0,
			}).Parent =
				card
			Theme.label({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = if id.multi
					then `⚠ It also carries another component tag — v1 expects one. {display.summary}`
					else display.summary,
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
				TextSize = 12,
				LayoutOrder = 1,
			}).Parent =
				card

			local row = Theme.make("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}) :: Frame
			row.Parent = card
			local change = Theme.button({
				Size = UDim2.new(0.5, -4, 1, 0),
				Text = "Change type",
				TextSize = 13,
			})
			change.Parent = row
			change.MouseButton1Click:Connect(function()
				chooserOpen = true
				refresh()
			end)
			local clearBtn = Theme.button({
				Size = UDim2.new(0.5, -4, 1, 0),
				Position = UDim2.new(0.5, 4, 0, 0),
				Text = "Clear",
				TextColor3 = Theme.COLOR.DANGER,
				TextSize = 13,
			})
			clearBtn.Parent = row
			clearBtn.MouseButton1Click:Connect(function()
				clearType({ instance }, all)
			end)

			if display.hint and display.hint ~= "" then
				order += 1
				note(display.hint, order)
			end

			order = buildForm(instance, id.schema, order)
			say(`{BuildAdmin.countInPlace(id.schema)} {display.title} in this place`)
			return
		end

		-- Untagged (or "Change type"): the chooser.
		if #id.unknownTags > 0 and not id.schema then
			order += 1
			note(
				`Tagged “{table.concat(id.unknownTags, ", ")}” — not a component this engine version knows.`,
				order
			)
			order += 1
			local clearBtn = Theme.button({
				Size = UDim2.new(1, 0, 0, 26),
				Text = "Clear",
				TextColor3 = Theme.COLOR.DANGER,
				TextSize = 13,
				LayoutOrder = order,
			})
			clearBtn.Parent = scroll
			clearBtn.MouseButton1Click:Connect(function()
				-- Pass the unknown tags we just listed, so Clear removes exactly what was shown.
				clearType({ instance }, all, id.unknownTags)
			end)
		end

		order += 1
		note(if chooserOpen then "Change this object to…" else "What is this object?", order, Theme.COLOR.TEXT)

		for _, schema in all do
			order += 1
			local eligible, reason = BuildAdmin.isEligible(instance, schema)
			local card = chooserCard(schema, BuildAdmin.displayOf(schema), eligible, reason, function(picked)
				applyType({ instance }, picked, all)
			end)
			card.LayoutOrder = order
			card.Parent = scroll
		end

		if chooserOpen then
			order += 1
			local cancel = Theme.button({
				Size = UDim2.new(1, 0, 0, 24),
				Text = "Cancel",
				TextSize = 12,
				LayoutOrder = order,
			})
			cancel.Parent = scroll
			cancel.MouseButton1Click:Connect(function()
				chooserOpen = false
				refresh()
			end)
		end
		say(`Selected: {instance.Name}`)
	end

	-- Re-render on selection change. Two guards: the window is rebuilt when the engine appears
	-- (so a stale connection must not touch a destroyed frame), and a refresh while the user is
	-- typing in one of our boxes would eat the value.
	local selfDirty = false
	local connection
	connection = Selection.SelectionChanged:Connect(function()
		if not container.Parent then
			connection:Disconnect()
			return
		end
		local focused = UserInputService:GetFocusedTextBox()
		if focused and focused:IsDescendantOf(container) then
			return
		end
		chooserOpen = false
		if container.Visible then
			refresh()
		else
			selfDirty = true
		end
	end)
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible and selfDirty then
			selfDirty = false
			refresh()
		end
	end)

	header.refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return BuildAdminUi
