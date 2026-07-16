--!nonstrict
--[[
	Theme — the plugin's shared visual system. One home for the style constants that used to be
	copy-pasted across every UI file, plus the small builders (instance factory, header, scroll,
	panel, styled controls) every page composes from. The palette is the dense/dark editor variant
	of docs/design-language.md.
]]

local Theme = {}

Theme.COLOR = {
	BG = Color3.fromRGB(18, 21, 28),
	RAIL = Color3.fromRGB(14, 17, 23), -- sidebar, a step darker than the page
	PANEL = Color3.fromRGB(28, 32, 42),
	PANEL_HOVER = Color3.fromRGB(34, 39, 52),
	FIELD = Color3.fromRGB(38, 43, 56),
	TEXT = Color3.fromRGB(235, 238, 245),
	DIM = Color3.fromRGB(150, 160, 180),
	ACCENT = Color3.fromRGB(120, 170, 255),
	DANGER = Color3.fromRGB(210, 90, 90),
	STROKE = Color3.fromRGB(210, 220, 245),
}

Theme.FONT = Enum.Font.GothamMedium
Theme.FONT_BOLD = Enum.Font.GothamBold
Theme.ROW_H = 26

-- Generic instance factory: props dict + optional children (reparented in order).
function Theme.make(class: string, props: { [string]: any }, children: { Instance }?): Instance
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

function Theme.corner(radius: number): Instance
	return Theme.make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Theme.stroke(transparency: number?): Instance
	return Theme.make("UIStroke", {
		Color = Theme.COLOR.STROKE,
		Transparency = transparency or 0.9,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.pad(left: number, right: number, top: number, bottom: number): Instance
	return Theme.make("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
	})
end

-- Styled primitives: sensible defaults, overridable via props.
function Theme.label(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.COLOR.TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = Theme.FONT,
	}
	for k, v in props do
		merged[k] = v
	end
	return Theme.make("TextLabel", merged) :: TextLabel
end

function Theme.button(props: { [string]: any }): TextButton
	local merged: { [string]: any } = {
		BackgroundColor3 = Theme.COLOR.FIELD,
		AutoButtonColor = true,
		TextColor3 = Theme.COLOR.TEXT,
		TextSize = 12,
		Font = Theme.FONT,
		BorderSizePixel = 0,
	}
	for k, v in props do
		merged[k] = v
	end
	return Theme.make("TextButton", merged, { Theme.corner(4) }) :: TextButton
end

function Theme.textBox(props: { [string]: any }): TextBox
	local merged: { [string]: any } = {
		BackgroundColor3 = Theme.COLOR.FIELD,
		TextColor3 = Theme.COLOR.TEXT,
		TextSize = 13,
		Font = Theme.FONT,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}
	for k, v in props do
		merged[k] = v
	end
	return Theme.make("TextBox", merged, {
		Theme.corner(4),
		Theme.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox
end

-- The standard 32px page header: bold title left, Refresh button right.
function Theme.header(container: Instance, title: string): { frame: Frame, refreshBtn: TextButton }
	local frame = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	}) :: Frame
	frame.Parent = container
	Theme.label({
		Size = UDim2.new(1, -84, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Text = title,
		TextSize = 15,
		Font = Theme.FONT_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent =
		frame
	local refreshBtn = Theme.button({
		Size = UDim2.fromOffset(72, 22),
		Position = UDim2.new(1, -80, 0.5, -11),
		BackgroundColor3 = Theme.COLOR.PANEL,
		Text = "Refresh",
	})
	refreshBtn.Parent = frame
	return { frame = frame, refreshBtn = refreshBtn }
end

-- The standard page scroll: CanvasSize reset + AutomaticCanvasSize.Y + list layout. Keep this
-- exact recipe — the explicit `CanvasSize = UDim2.new()` matters (the default canvas adds
-- phantom scroll).
function Theme.scroll(offsetTop: number, offsetBottom: number, listPadding: number?): ScrollingFrame
	return Theme.make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -(offsetTop + offsetBottom)),
		Position = UDim2.fromOffset(0, offsetTop),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		Theme.make("UIListLayout", {
			Padding = UDim.new(0, listPadding or 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Theme.pad(10, 10, 6, 12),
	}) :: ScrollingFrame
end

-- The standard content panel: PANEL background, rounded, subtle stroke, padded list layout.
-- Grows with content by default (AutomaticSize.Y); override Size/AutomaticSize for fixed panels.
function Theme.panel(): Frame
	return Theme.make("Frame", {
		BackgroundColor3 = Theme.COLOR.PANEL,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Theme.corner(8),
		Theme.stroke(),
		Theme.pad(8, 8, 6, 8),
		Theme.make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame
end

-- A small count/status pill (rail badges, entry badges).
function Theme.badge(text: string, textColor: Color3?): TextLabel
	return Theme.make("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 14),
		BackgroundColor3 = Theme.COLOR.FIELD,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = textColor or Theme.COLOR.DIM,
		TextSize = 10,
		Font = Theme.FONT,
	}, {
		Theme.corner(7),
		Theme.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextLabel
end

-- MouseEnter/Leave background tint for custom (non-AutoButtonColor) elements.
function Theme.hover(gui: GuiObject, base: Color3, hoverColor: Color3)
	gui.MouseEnter:Connect(function()
		gui.BackgroundColor3 = hoverColor
	end)
	gui.MouseLeave:Connect(function()
		gui.BackgroundColor3 = base
	end)
end

return Theme
