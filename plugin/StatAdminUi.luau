--!nonstrict
--[[
	StatAdminUi — builds the dock-widget content. A thin layer over StatAdmin (the logic):
	it never touches the config instance itself. Edits are routed through `applyEdit` /
	`applyReset` callbacks the plugin main supplies (they wrap the StatAdmin call in a
	ChangeHistoryService recording, then refresh). Styling follows docs/design-language.md.
]]

local StatAdminUi = {}

local COL_BG = Color3.fromRGB(18, 21, 28)
local COL_PANEL = Color3.fromRGB(28, 32, 42)
local COL_TEXT = Color3.fromRGB(235, 238, 245)
local COL_DIM = Color3.fromRGB(150, 160, 180)
local COL_ACCENT = Color3.fromRGB(120, 170, 255) -- marks an overridden field
local COL_FIELD = Color3.fromRGB(38, 43, 56)
local FONT = Enum.Font.GothamMedium
local ROW_H = 26
local FOOTER_H = 36 -- the Preview / Clear control bar at the bottom

local function make(class: string, props: { [string]: any }, children: { Instance }?): Instance
	local inst = Instance.new(class)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	return inst
end

local function corner(radius: number): Instance
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

-- A single field row: [reset] label .... control. `applyEdit/applyReset` take (stat, attr, …).
local function buildRow(stat: string, spec: any, eff: any, applyEdit, applyReset): Instance
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
	})

	-- reset dot/button — accent when overridden, dim otherwise; click removes the attribute.
	local reset = make("TextButton", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(0, 0, 0.5, -9),
		BackgroundColor3 = COL_FIELD,
		AutoButtonColor = true,
		Text = eff.hasOverride and "●" or "○",
		TextColor3 = eff.hasOverride and COL_ACCENT or COL_DIM,
		TextSize = 12,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	reset.Parent = row
	reset.MouseButton1Click:Connect(function()
		applyReset(stat, spec.attr)
	end)

	make("TextLabel", {
		Size = UDim2.new(0.42, -28, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		BackgroundTransparency = 1,
		Text = spec.label,
		TextColor3 = eff.hasOverride and COL_TEXT or COL_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = FONT,
	}).Parent =
		row

	local controlPos = UDim2.new(0.42, 4, 0, 2)
	local controlSize = UDim2.new(0.58, -4, 0, ROW_H - 4)

	if spec.kind == "boolean" or spec.kind == "enum" then
		-- a click-to-cycle button (boolean: true/false; enum: through the choices)
		local control = make("TextButton", {
			Size = controlSize,
			Position = controlPos,
			BackgroundColor3 = COL_FIELD,
			AutoButtonColor = true,
			Text = tostring(eff.value),
			TextColor3 = COL_TEXT,
			TextSize = 13,
			Font = FONT,
			BorderSizePixel = 0,
		}, { corner(4) })
		control.Parent = row
		control.MouseButton1Click:Connect(function()
			local nextValue: any
			if spec.kind == "boolean" then
				nextValue = not (eff.value == true)
			else
				local choices = spec.choices
				local i = table.find(choices, tostring(eff.value)) or 0
				nextValue = choices[(i % #choices) + 1]
			end
			applyEdit(stat, spec.attr, nextValue, eff.default)
		end)
	else
		-- number / string: a text box committed on focus loss
		local box = make("TextBox", {
			Size = controlSize,
			Position = controlPos,
			BackgroundColor3 = COL_FIELD,
			Text = tostring(eff.value),
			PlaceholderText = tostring(eff.default),
			TextColor3 = COL_TEXT,
			TextSize = 13,
			Font = FONT,
			ClearTextOnFocus = false,
			BorderSizePixel = 0,
		}, { corner(4), make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
		box.Parent = row
		box.FocusLost:Connect(function()
			applyEdit(stat, spec.attr, box.Text, eff.default)
		end)
	end

	return row
end

-- Mount the widget UI into `container`. Returns { refresh } — call refresh() after any edit
-- or when the engine sync changes. `StatAdmin` is the logic module; the two callbacks route
-- writes through the plugin main (ChangeHistory + refresh).
function StatAdminUi.mount(
	container: Instance,
	StatAdmin: any,
	applyEdit,
	applyReset,
	applyPreview,
	applyClear
): { refresh: () -> () }
	for _, child in container:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
	(container :: any).BackgroundColor3 = COL_BG

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	header.Parent = container
	make("TextLabel", {
		Size = UDim2.new(1, -84, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "Survival Stats",
		TextColor3 = COL_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		Font = Enum.Font.GothamBold,
	}).Parent =
		header
	local refreshBtn = make("TextButton", {
		Size = UDim2.fromOffset(72, 22),
		Position = UDim2.new(1, -80, 0.5, -11),
		BackgroundColor3 = COL_PANEL,
		AutoButtonColor = true,
		Text = "Refresh",
		TextColor3 = COL_TEXT,
		TextSize = 12,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	refreshBtn.Parent = header

	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -(32 + FOOTER_H)),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 12),
		}),
	})
	scroll.Parent = container

	-- Footer: the edit-mode HUD preview controls. Preview paints resolved icons + sample fills
	-- onto the StarterGui HUD (so you see play-time styling without pressing Play); Clear restores.
	local footer = make("Frame", {
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		Position = UDim2.new(0, 0, 1, -FOOTER_H),
		BackgroundColor3 = COL_PANEL,
		BorderSizePixel = 0,
	})
	footer.Parent = container
	local previewBtn = make("TextButton", {
		Size = UDim2.fromOffset(92, 22),
		Position = UDim2.new(0, 10, 0.5, -11),
		BackgroundColor3 = COL_FIELD,
		AutoButtonColor = true,
		Text = "Preview HUD",
		TextColor3 = COL_TEXT,
		TextSize = 12,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	previewBtn.Parent = footer
	local clearBtn = make("TextButton", {
		Size = UDim2.fromOffset(56, 22),
		Position = UDim2.new(0, 108, 0.5, -11),
		BackgroundColor3 = COL_FIELD,
		AutoButtonColor = true,
		Text = "Clear",
		TextColor3 = COL_DIM,
		TextSize = 12,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	clearBtn.Parent = footer
	local status = make("TextLabel", {
		Size = UDim2.new(1, -184, 1, 0),
		Position = UDim2.fromOffset(174, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = COL_DIM,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 11,
		Font = FONT,
	})
	status.Parent = footer

	previewBtn.MouseButton1Click:Connect(function()
		local res = applyPreview and applyPreview()
		if typeof(res) == "table" then
			status.Text = if res.ok then `previewing {res.count}` else (res.reason or "no HUD found")
		end
	end)
	clearBtn.MouseButton1Click:Connect(function()
		local res = applyClear and applyClear()
		if typeof(res) == "table" then
			status.Text = if res.ok then "cleared" else (res.reason or "")
		end
	end)

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end

		local roster = StatAdmin.readRoster()
		if not roster.ok then
			make("TextLabel", {
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundTransparency = 1,
				Text = roster.reason or "Engine not found.",
				TextColor3 = COL_DIM,
				TextWrapped = true,
				TextSize = 13,
				Font = FONT,
			}).Parent =
				scroll
			return
		end

		local order = 0
		for _, entry in roster.stats do
			order += 1
			local section = make("Frame", {
				BackgroundColor3 = COL_PANEL,
				BorderSizePixel = 0,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 22 + ROW_H * #StatAdmin.TUNABLE + 8),
				AutomaticSize = Enum.AutomaticSize.None,
			}, {
				corner(8),
				make("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
				make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			section.Parent = scroll

			make("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				Text = entry.name,
				TextColor3 = COL_TEXT,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 14,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 0,
			}).Parent =
				section

			for i, spec in StatAdmin.TUNABLE do
				local eff = StatAdmin.readEffective(entry.name, spec.attr, entry.defaults[spec.attr])
				local row = buildRow(entry.name, spec, eff, applyEdit, applyReset)
				row.LayoutOrder = i
				row.Parent = section
			end
		end
	end

	refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return StatAdminUi
