--!nonstrict
--[[
	UiFallback — the zero-setup safety net for the menu + hotbar. CLIENT-ONLY.

	If no authored `SurvivalMenu` / `SurvivalHotbar` template reaches the player (none mounted,
	bundled, or installed), this builds a deliberately minimal, unstyled version using the SAME
	marker attributes the templates use, so the binders (PanelManager / InventoryUi / Hotbar /
	CharacterSheet) drive it identically. The authored templates are the real thing — this is
	just the floor, and (like HudFallback) the only other code that builds UI instances. Zero
	asset IDs.
]]

local UiConfig = require(script.Parent.Parent.shared.UiConfig)

local UiFallback = {}

local EQUIP_SLOTS = {
	{ "head", "Head" },
	{ "top", "Top" },
	{ "pants", "Pants" },
	{ "shoes", "Shoes" },
	{ "back", "Back" },
	{ "quiver", "Quiver" },
}
local ATTR_ROWS = { "Health", "Energy", "Hunger", "Thirst", "Fatigue" }
local TABS = {
	{ "inventory", "Inventory" },
	{ "character", "Character" },
	{ "codex", "Codex" },
	{ "achievements", "Achievements" },
	{ "quests", "Quests" },
}

-- Tiny instance builder: new(class, props, attrs?, children?).
local function new(
	class: string,
	props: { [string]: any },
	attrs: { [string]: any }?,
	children: { Instance }?
): Instance
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if attrs then
		for k, v in attrs do
			inst:SetAttribute(k, v)
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	return inst
end

local function corner(r: number): Instance
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(theme: any): Instance
	return new("UIStroke", { Color = theme.StrokeColor, Transparency = theme.StrokeTransparency, Thickness = 1 })
end

local function slotTemplate(theme: any): Instance
	return new("ImageButton", {
		Name = "SlotTemplate",
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = theme.SlotColor,
		BackgroundTransparency = 0.25,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Image = "",
		Visible = false,
	}, { SlotTemplate = true }, {
		corner(6),
		stroke(theme),
		new("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(0.78, 0.78),
			Position = UDim2.fromScale(0.11, 0.11),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Image = "",
			Visible = false,
			ZIndex = 2,
		}),
		new("TextLabel", {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -3, 1, -2),
			Size = UDim2.fromOffset(30, 16),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = theme.Text,
			Font = theme.FontBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
		new(
			"Frame",
			{ Name = "Selected", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 2 },
			nil,
			{
				corner(6),
				new("UIStroke", { Color = theme.Accent, Thickness = 2 }),
			}
		),
	})
end

local function buildInventoryContent(theme: any): Instance
	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(0.6, -6, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
	}, { InventoryGrid = true }, {
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(64, 64),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		slotTemplate(theme),
	})

	local weight = new("Frame", {
		Name = "WeightReadout",
		Position = UDim2.new(0, 0, 1, -46),
		Size = UDim2.new(0.6, -6, 0, 20),
		BackgroundColor3 = theme.SlotColor,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, { WeightReadout = true }, {
		corner(6),
		new(
			"Frame",
			{ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = theme.Ok, BorderSizePixel = 0 },
			nil,
			{ corner(6) }
		),
		new("TextLabel", {
			Name = "Value",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = theme.Text,
			Font = theme.Font,
			TextSize = 12,
			ZIndex = 2,
		}),
	})

	local slotReadout = new("Frame", {
		Name = "SlotReadout",
		Position = UDim2.new(0, 0, 1, -22),
		Size = UDim2.new(0.6, -6, 0, 18),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { SlotReadout = true }, {
		new("TextLabel", {
			Name = "Value",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = theme.TextSecondary,
			Font = theme.Font,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	local actions = {}
	for i, spec in { { "use", "Use" }, { "equip", "Equip" }, { "hotbar", "→ Hotbar" }, { "split", "Split" } } do
		table.insert(
			actions,
			new("TextButton", {
				Name = "Action_" .. spec[1],
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = theme.SlotColor,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Text = spec[2],
				TextColor3 = theme.Text,
				Font = theme.Font,
				TextSize = 13,
				LayoutOrder = i,
			}, { Action = spec[1] }, { corner(6) })
		)
	end
	local detail = new("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.38, 1),
		BackgroundColor3 = theme.SlotColor,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, { ItemDetail = true }, {
		corner(8),
		stroke(theme),
		new("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Image = "",
			Visible = false,
		}),
		new("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = theme.Text,
			Font = theme.FontBold,
			TextSize = 15,
		}),
		new("TextLabel", {
			Name = "Description",
			Position = UDim2.fromOffset(0, 98),
			Size = UDim2.new(1, 0, 0, 90),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = theme.TextSecondary,
			Font = theme.Font,
			TextSize = 12,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		new(
			"Frame",
			{
				Name = "Actions",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 122),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			},
			nil,
			(function()
				local kids = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				}
				for _, a in actions do
					table.insert(kids, a)
				end
				return kids
			end)()
		),
	})

	return new("Frame", {
		Name = "Content_inventory",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = true,
	}, { TabContent = "inventory" }, { grid, weight, slotReadout, detail })
end

local function buildCharacterContent(theme: any): Instance
	local equipKids = {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, spec in EQUIP_SLOTS do
		table.insert(
			equipKids,
			new("Frame", {
				Name = "Equip_" .. spec[1],
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = theme.SlotColor,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, { EquipSlot = spec[1] }, {
				corner(6),
				new("ImageLabel", {
					Name = "Icon",
					Position = UDim2.fromOffset(6, 6),
					Size = UDim2.fromOffset(32, 32),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Image = "",
					Visible = false,
				}),
				new("TextLabel", {
					Name = "SlotLabel",
					Position = UDim2.fromOffset(46, 0),
					Size = UDim2.new(0, 70, 1, 0),
					BackgroundTransparency = 1,
					Text = spec[2],
					TextColor3 = theme.TextSecondary,
					Font = theme.Font,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				new("TextLabel", {
					Name = "Name",
					Position = UDim2.fromOffset(120, 0),
					Size = UDim2.new(1, -126, 1, 0),
					BackgroundTransparency = 1,
					Text = "",
					TextColor3 = theme.Text,
					Font = theme.Font,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		)
	end
	local equipment = new(
		"Frame",
		{ Name = "Equipment", Size = UDim2.new(0.46, -6, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0 },
		nil,
		equipKids
	)

	local attrKids = {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		new("TextLabel", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = "Attributes",
			TextColor3 = theme.Text,
			Font = theme.FontBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
		}),
	}
	for i, attrName in ATTR_ROWS do
		table.insert(
			attrKids,
			new("Frame", {
				Name = "Attr_" .. attrName,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, { AttributeReadout = attrName }, {
				new("TextLabel", {
					Name = "Label",
					Size = UDim2.fromScale(0.6, 1),
					BackgroundTransparency = 1,
					Text = attrName,
					TextColor3 = theme.TextSecondary,
					Font = theme.Font,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				new("TextLabel", {
					Name = "Value",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromScale(0.4, 1),
					BackgroundTransparency = 1,
					Text = "0",
					TextColor3 = theme.Text,
					Font = theme.FontBold,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
			})
		)
	end
	local attributes = new(
		"Frame",
		{
			Name = "Attributes",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundColor3 = theme.SlotColor,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		},
		nil,
		(function()
			table.insert(attrKids, 1, corner(8))
			table.insert(
				attrKids,
				2,
				new("UIPadding", {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				})
			)
			return attrKids
		end)()
	)

	return new("Frame", {
		Name = "Content_character",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, { TabContent = "character" }, { equipment, attributes })
end

local function buildScaffold(theme: any, id: string, text: string): Instance
	return new("Frame", {
		Name = "Content_" .. id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, { TabContent = id }, {
		new("TextLabel", {
			Name = "Placeholder",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = theme.TextSecondary,
			Font = theme.Font,
			TextSize = 16,
		}),
	})
end

function UiFallback.buildMenu(playerGui: Instance)
	local theme = UiConfig.get().Theme

	local tabKids = {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, spec in TABS do
		table.insert(
			tabKids,
			new("TextButton", {
				Name = "Tab_" .. spec[1],
				Size = UDim2.new(0, 104, 1, 0),
				BackgroundColor3 = theme.SlotColor,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Text = spec[2],
				TextColor3 = theme.Text,
				Font = theme.Font,
				TextSize = 14,
				LayoutOrder = i,
			}, { InventoryTab = spec[1] }, {
				corner(6),
				new("Frame", {
					Name = "Selected",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -2),
					Size = UDim2.new(0.8, 0, 0, 3),
					BackgroundColor3 = theme.Accent,
					BorderSizePixel = 0,
					Visible = false,
				}, nil, { corner(2) }),
			})
		)
	end
	local tabBar = new("Frame", {
		Name = "TabBar",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, -34, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { TabBar = true }, tabKids)

	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { TabContentHost = true }, {
		buildInventoryContent(theme),
		buildCharacterContent(theme),
		buildScaffold(theme, "codex", "Codex — coming soon"),
		buildScaffold(theme, "achievements", "Achievements — coming soon"),
		buildScaffold(theme, "quests", "Quests — coming soon"),
	})

	local root = new(
		"Frame",
		{
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(640, 420),
			BackgroundColor3 = theme.PanelColor,
			BackgroundTransparency = theme.PanelTransparency,
			BorderSizePixel = 0,
		},
		nil,
		{
			corner(theme.CornerRadius),
			stroke(theme),
			new("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}),
			new("TextButton", {
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(26, 26),
				BackgroundTransparency = 1,
				Text = "X",
				TextColor3 = theme.TextSecondary,
				Font = theme.FontBold,
				TextSize = 16,
				ZIndex = 5,
			}, { MenuClose = true }),
			tabBar,
			content,
		}
	)

	new("ScreenGui", {
		Name = "SurvivalMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = UiConfig.get().DisplayOrder.Menu,
		Enabled = false,
	}, nil, { root }).Parent =
		playerGui
end

function UiFallback.buildHotbar(playerGui: Instance)
	local theme = UiConfig.get().Theme
	local slots = {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for n = 1, 9 do
		table.insert(
			slots,
			new("ImageButton", {
				Name = "Slot" .. n,
				Size = UDim2.fromOffset(58, 58),
				BackgroundColor3 = theme.SlotColor,
				BackgroundTransparency = 0.25,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Image = "",
				LayoutOrder = n,
			}, { HotbarSlot = n }, {
				corner(6),
				stroke(theme),
				new("ImageLabel", {
					Name = "Icon",
					Size = UDim2.fromScale(0.78, 0.78),
					Position = UDim2.fromScale(0.11, 0.11),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Image = "",
					Visible = false,
					ZIndex = 2,
				}),
				new("TextLabel", {
					Name = "Key",
					Position = UDim2.fromOffset(3, 2),
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Text = tostring(n),
					TextColor3 = theme.TextSecondary,
					Font = theme.Font,
					TextSize = 11,
					ZIndex = 3,
				}),
				new("TextLabel", {
					Name = "Count",
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -3, 1, -2),
					Size = UDim2.fromOffset(28, 14),
					BackgroundTransparency = 1,
					Text = "",
					TextColor3 = theme.Text,
					Font = theme.FontBold,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 3,
				}),
				new("Frame", {
					Name = "Active",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Visible = false,
					ZIndex = 2,
				}, nil, { corner(6), new("UIStroke", { Color = theme.Accent, Thickness = 2 }) }),
			})
		)
	end
	local root = new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(0, 70),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
	}, nil, slots)
	new("ScreenGui", {
		Name = "SurvivalHotbar",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = UiConfig.get().DisplayOrder.Hotbar,
	}, nil, { root }).Parent =
		playerGui
end

return UiFallback
