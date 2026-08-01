--!nonstrict
--[[
	FieldRow — the shared schema-field row: [○/●] label … [control], plus an optional wrapped help
	line underneath. The visual language is the Engine Config editor's (a filled dot means "you set
	this"; an empty dot means "following the default"), so every schema-driven editor in the plugin
	looks and behaves the same.

	Controls by kind: boolean/enum cycle on click; everything else is a TextBox committed on focus
	loss, showing the default as its placeholder. When a field declares `ref` (a content category),
	the box gains a ⌄ button that cycles the ids authored in that category — so a creator picks
	"oak_tree" instead of remembering it.
]]

local Theme = require(script.Parent.Theme)
local Field = require(script.Parent.Field)

local FieldRow = {}

local ROW_H = Theme.ROW_H

-- opts = {
--   spec,                       -- AttributeSpec
--   state,                      -- { value, default, hasOverride, typeMismatch? }
--   onCommit(raw) -> (),        -- commit an edit (blank = reset)
--   onReset() -> (),            -- the ○/● dot
--   choices: { string }?,       -- resolved `ref` ids, for the ⌄ picker
-- }
function FieldRow.build(opts: any): Frame
	local spec, state = opts.spec, opts.state
	local hasHelp = typeof(spec.help) == "string" and spec.help ~= ""

	local row = Theme.make("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Theme.make("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 1),
		}),
	}) :: Frame

	local top = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}) :: Frame
	top.Parent = row

	-- Override dot: filled + accented when this instance sets the attribute.
	local dot = Theme.button({
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(0, 4),
		Text = if state.hasOverride then "●" else "○",
		TextColor3 = if state.hasOverride then Theme.COLOR.ACCENT else Theme.COLOR.DIM,
		BackgroundTransparency = 1,
		TextSize = 13,
	})
	dot.Parent = top
	dot.MouseButton1Click:Connect(function()
		opts.onReset()
	end)

	local warn = if state.typeMismatch then " ⚠" else ""
	Theme.label({
		Size = UDim2.new(0.42, -22, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		Text = spec.label .. warn,
		TextColor3 = if state.hasOverride then Theme.COLOR.TEXT else Theme.COLOR.DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		top

	local controlX = UDim2.new(0.42, 4, 0, 3)
	local controlW = UDim2.new(0.58, -4, 0, ROW_H - 6)

	if spec.kind == "boolean" or spec.kind == "enum" then
		local current = Field.format(spec, state.value)
		local control = Theme.button({
			Size = controlW,
			Position = controlX,
			Text = if current == "" then "(blank)" else current,
			TextColor3 = if state.hasOverride then Theme.COLOR.TEXT else Theme.COLOR.DIM,
			TextSize = 13,
		})
		control.Parent = top
		control.MouseButton1Click:Connect(function()
			if spec.kind == "boolean" then
				opts.onCommit(not (state.value == true))
				return
			end
			local choices = spec.choices or {}
			local index = 0
			for i, choice in choices do
				if choice == current then
					index = i
					break
				end
			end
			local nextChoice = choices[(index % math.max(1, #choices)) + 1]
			if nextChoice ~= nil then
				opts.onCommit(nextChoice)
			end
		end)
	else
		local pickable = opts.choices and #opts.choices > 0
		local box = Theme.textBox({
			Size = if pickable then UDim2.new(0.58, -28, 0, ROW_H - 6) else controlW,
			Position = controlX,
			Text = if state.hasOverride then Field.format(spec, state.value) else "",
			PlaceholderText = spec.placeholder or Field.format(spec, spec.default),
		})
		box.Parent = top
		box.FocusLost:Connect(function()
			opts.onCommit(box.Text)
		end)

		if pickable then
			-- Cycle the ids authored in the referenced content category.
			local pick = Theme.button({
				Size = UDim2.fromOffset(22, ROW_H - 6),
				Position = UDim2.new(1, -22, 0, 3),
				Text = "⌄",
				TextSize = 13,
			})
			pick.Parent = top
			pick.MouseButton1Click:Connect(function()
				local choices = opts.choices
				local current = if state.hasOverride then Field.format(spec, state.value) else ""
				local index = 0
				for i, choice in choices do
					if choice == current then
						index = i
						break
					end
				end
				opts.onCommit(choices[(index % #choices) + 1])
			end)
		end
	end

	if hasHelp then
		-- `row` owns a UIListLayout, which overwrites child Position — so the indent under the
		-- label column has to come from padding, not Position.
		local help = Theme.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = spec.help,
			TextColor3 = Theme.COLOR.DIM,
			TextWrapped = true,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2,
		})
		Theme.pad(22, 0, 0, 2).Parent = help
		help.Parent = row
	end

	return row
end

return FieldRow
