--!nonstrict
--[[
	ConfigAdminUi — the Engine Config editor pages (issue #21). One sidebar page per Config
	section; each page renders its groups as headed panels of typed field rows (the StatAdminUi
	row pattern, generalized): reset dot ●/○, label, and a control per kind — number/string
	TextBox (placeholder = engine default), boolean/enum click-cycle, color3 TextBox "R, G, B"
	with a live swatch, font TextBox with a cycle button over common fonts. All writes route
	through the plugin main's record() wrappers (one undo step each), deltas-only via ConfigAdmin.
]]

local Theme = require(script.Parent.Theme)

local ConfigAdminUi = {}

local ROW_H = Theme.ROW_H
local FOOTER_H = 36

-- The click-cycle list for font fields (any valid Enum.Font name can still be typed).
local COMMON_FONTS = {
	"Gotham",
	"GothamMedium",
	"GothamBold",
	"GothamBlack",
	"SourceSans",
	"SourceSansBold",
	"Arial",
	"ArialBold",
	"Merriweather",
	"Bangers",
	"PermanentMarker",
}

-- One field row. `groupName` may be nil (root attributes).
local function buildRow(ConfigAdmin, sectionId, groupName, field, eff, applyEdit, applyReset): Instance
	local row = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
	})

	local reset = Theme.button({
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(0, 0, 0.5, -9),
		Text = eff.hasOverride and "●" or "○",
		TextColor3 = eff.hasOverride and Theme.COLOR.ACCENT or Theme.COLOR.DIM,
	})
	reset.Parent = row
	reset.MouseButton1Click:Connect(function()
		applyReset(sectionId, groupName, field.attr)
	end)

	Theme.label({
		Size = UDim2.new(0.42, -28, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		Text = field.label,
		TextColor3 = eff.hasOverride and Theme.COLOR.TEXT or Theme.COLOR.DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		row

	local controlPos = UDim2.new(0.42, 4, 0, 2)
	local controlSize = UDim2.new(0.58, -4, 0, ROW_H - 4)

	if field.kind == "boolean" or field.kind == "enum" then
		local control = Theme.button({
			Size = controlSize,
			Position = controlPos,
			Text = ConfigAdmin.formatValue(field, eff.value),
			TextSize = 13,
		})
		control.Parent = row
		control.MouseButton1Click:Connect(function()
			local nextValue: any
			if field.kind == "boolean" then
				nextValue = not (eff.value == true)
			else
				local choices = field.choices or {}
				local i = table.find(choices, tostring(eff.value)) or 0
				nextValue = choices[(i % #choices) + 1]
			end
			applyEdit(sectionId, groupName, field, nextValue, eff.default)
		end)
	elseif field.kind == "color3" then
		-- [ R, G, B text box ][ swatch ] — the swatch previews the effective color live.
		local box = Theme.textBox({
			Size = UDim2.new(0.58, -28, 0, ROW_H - 4),
			Position = controlPos,
			Text = ConfigAdmin.formatValue(field, eff.value),
			PlaceholderText = ConfigAdmin.formatValue(field, eff.default),
		})
		box.Parent = row
		local swatch = Theme.make("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, -18, 0.5, -9),
			BackgroundColor3 = if typeof(eff.value) == "Color3" then eff.value else Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, { Theme.corner(4), Theme.stroke(0.7) })
		swatch.Parent = row
		box.FocusLost:Connect(function()
			applyEdit(sectionId, groupName, field, box.Text, eff.default)
		end)
	elseif field.kind == "font" then
		-- [ font name box ][ ↻ cycle ] — cycles common fonts; any Enum.Font name can be typed.
		local box = Theme.textBox({
			Size = UDim2.new(0.58, -28, 0, ROW_H - 4),
			Position = controlPos,
			Text = ConfigAdmin.formatValue(field, eff.value),
			PlaceholderText = ConfigAdmin.formatValue(field, eff.default),
		})
		box.Parent = row
		box.FocusLost:Connect(function()
			applyEdit(sectionId, groupName, field, box.Text, eff.default)
		end)
		local cycle = Theme.button({
			Size = UDim2.fromOffset(22, ROW_H - 4),
			Position = UDim2.new(1, -22, 0, 2),
			Text = "↻",
			TextColor3 = Theme.COLOR.DIM,
		})
		cycle.Parent = row
		cycle.MouseButton1Click:Connect(function()
			local current = ConfigAdmin.formatValue(field, eff.value)
			local i = table.find(COMMON_FONTS, current) or 0
			applyEdit(sectionId, groupName, field, COMMON_FONTS[(i % #COMMON_FONTS) + 1], eff.default)
		end)
	else
		local box = Theme.textBox({
			Size = controlSize,
			Position = controlPos,
			Text = ConfigAdmin.formatValue(field, eff.value),
			PlaceholderText = ConfigAdmin.formatValue(field, eff.default),
		})
		box.Parent = row
		box.FocusLost:Connect(function()
			applyEdit(sectionId, groupName, field, box.Text, eff.default)
		end)
	end

	return row
end

-- Mount one section's page. Re-reads the schema on every refresh (self-heals after re-syncs).
local function mountSection(
	container: Frame,
	ConfigAdmin: any,
	sectionId: string,
	applyEdit,
	applyReset,
	applyResetSection
): { refresh: () -> () }
	local header = Theme.header(container, "Engine Config")
	local scroll = Theme.scroll(32, FOOTER_H, 6)
	scroll.Parent = container

	local footer = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		Position = UDim2.new(0, 0, 1, -FOOTER_H),
		BackgroundColor3 = Theme.COLOR.PANEL,
		BorderSizePixel = 0,
	})
	footer.Parent = container
	local resetBtn = Theme.button({
		Size = UDim2.fromOffset(96, 22),
		Position = UDim2.new(0, 10, 0.5, -11),
		Text = "Reset section",
		TextColor3 = Theme.COLOR.DANGER,
	})
	resetBtn.Parent = footer
	local status = Theme.label({
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(112, 0),
		Text = "",
		TextColor3 = Theme.COLOR.DIM,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 11,
	})
	status.Parent = footer

	local currentSection: any = nil

	-- Route a rejected edit's reason to the footer (set AFTER record()'s refresh, so it sticks).
	local function editField(editSectionId, groupName, field, raw, default)
		local res = applyEdit(editSectionId, groupName, field, raw, default)
		if typeof(res) == "table" and res.ok == false and res.error then
			status.Text = `✗ {field.label}: {res.error}`
		end
		return res
	end

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end

		local schema = ConfigAdmin.readSchema()
		if not schema.ok then
			currentSection = nil
			status.Text = ""
			Theme.label({
				Size = UDim2.new(1, 0, 0, 80),
				Text = schema.reason or "Engine not found.",
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
			}).Parent =
				scroll
			return
		end

		local section: any = nil
		for _, s in schema.sections do
			if s.id == sectionId then
				section = s
				break
			end
		end
		if not section then
			status.Text = ""
			Theme.label({
				Size = UDim2.new(1, 0, 0, 60),
				Text = `Section '{sectionId}' is not in this engine's schema (older engine?).`,
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
			}).Parent =
				scroll
			return
		end
		currentSection = section
		local defaults = schema.defaults[sectionId] or {}

		local order = 0
		Theme.label({
			Size = UDim2.new(1, 0, 0, 20),
			Text = section.title,
			Font = Theme.FONT_BOLD,
			TextSize = 15,
			LayoutOrder = order,
		}).Parent =
			scroll

		if section.note then
			order += 1
			Theme.label({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = section.note,
				TextColor3 = Theme.COLOR.DIM,
				TextWrapped = true,
				TextSize = 12,
				LayoutOrder = order,
			}).Parent =
				scroll
		end

		for _, group in section.groups do
			order += 1
			-- Theme.panel() auto-sizes (AutomaticSize.Y) — a fixed-height formula here would
			-- miss the panel's own padding + per-row list gaps and clip the last row.
			local panel = Theme.panel()
			panel.LayoutOrder = order
			panel.Parent = scroll

			Theme.label({
				Size = UDim2.new(1, 0, 0, 22),
				Text = group.label,
				Font = Theme.FONT_BOLD,
				TextSize = 14,
				LayoutOrder = 0,
			}).Parent =
				panel

			local groupDefaults = if group.name then defaults[group.name] else defaults
			for i, field in group.fields do
				local default = if typeof(groupDefaults) == "table" then groupDefaults[field.attr] else nil
				local eff = ConfigAdmin.readEffective(section.id, group.name, field.attr, default)
				local row = buildRow(ConfigAdmin, section.id, group.name, field, eff, editField, applyReset)
				row.LayoutOrder = i
				row.Parent = panel
			end
		end

		local overridden = ConfigAdmin.countOverrides(section)
		status.Text = if overridden == 0
			then "no overrides — engine defaults"
			else `{overridden} field(s) overridden · applies on next Play`
	end

	resetBtn.MouseButton1Click:Connect(function()
		if currentSection then
			applyResetSection(currentSection)
		end
	end)
	header.refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

-- Build the Nav pages: one per section when the engine is present, else a single explainer page
-- whose Refresh triggers `onEngineFound` (the plugin main rebuilds the whole window) once the
-- engine appears — the page list is otherwise fixed for the life of the mount.
function ConfigAdminUi.pages(ConfigAdmin: any, applyEdit, applyReset, applyResetSection, onEngineFound): { any }
	local pages = {}
	local schema = ConfigAdmin.readSchema()
	if schema.ok then
		for _, section in schema.sections do
			table.insert(pages, {
				id = "config/" .. section.id,
				label = section.title,
				section = "Engine Config",
				mount = function(frame)
					return mountSection(frame, ConfigAdmin, section.id, applyEdit, applyReset, applyResetSection)
				end,
			})
		end
	else
		table.insert(pages, {
			id = "config/unavailable",
			label = "Engine Config",
			section = "Engine Config",
			mount = function(frame)
				local header = Theme.header(frame, "Engine Config")
				local message = Theme.label({
					Size = UDim2.new(1, -24, 0, 100),
					Position = UDim2.fromOffset(12, 40),
					Text = (schema.reason or "Engine not found.")
						.. " Once the engine is in the place, click Refresh to load the sections.",
					TextColor3 = Theme.COLOR.DIM,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
				})
				message.Parent = frame
				local function refresh()
					local retry = ConfigAdmin.readSchema()
					if retry.ok and onEngineFound then
						onEngineFound() -- the plugin main remounts the window with the full page list
					end
				end
				header.refreshBtn.MouseButton1Click:Connect(refresh)
				return { refresh = refresh }
			end,
		})
	end
	return pages
end

return ConfigAdminUi
