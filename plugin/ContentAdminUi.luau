--!nonstrict
--[[
	ContentAdminUi — the dock-widget UI for the no-code content builder. A thin layer over
	ContentAdmin (the logic): it renders an Items section and a Gatherables section, each with a
	"create" row and one editable panel per entry (field rows + Delete). Edits route through the
	applySet / applyCreate / applyDelete callbacks the plugin main supplies (which wrap the
	ContentAdmin call in a ChangeHistoryService recording, then refresh). Styling matches
	StatAdminUi / docs/design-language.md.
]]

local ContentAdminUi = {}

local COL_BG = Color3.fromRGB(18, 21, 28)
local COL_PANEL = Color3.fromRGB(28, 32, 42)
local COL_TEXT = Color3.fromRGB(235, 238, 245)
local COL_DIM = Color3.fromRGB(150, 160, 180)
local COL_FIELD = Color3.fromRGB(38, 43, 56)
local COL_ACCENT = Color3.fromRGB(120, 170, 255)
local COL_DANGER = Color3.fromRGB(210, 90, 90)
local FONT = Enum.Font.GothamMedium
local ROW_H = 26

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

-- A single field row: label .... control (TextBox committed on focus loss).
local function buildField(catKey: string, id: string, field: any, value: any, applySet): Instance
	local row = make("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 })

	make("TextLabel", {
		Size = UDim2.fromScale(0.4, 1),
		BackgroundTransparency = 1,
		Text = field.label,
		TextColor3 = COL_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = FONT,
	}).Parent =
		row

	local box = make("TextBox", {
		Size = UDim2.new(0.6, -4, 0, ROW_H - 4),
		Position = UDim2.new(0.4, 4, 0, 2),
		BackgroundColor3 = COL_FIELD,
		Text = tostring(value),
		PlaceholderText = field.placeholder or tostring(field.default),
		TextColor3 = COL_TEXT,
		TextSize = 13,
		Font = FONT,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, { corner(4), make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	box.Parent = row
	box.FocusLost:Connect(function()
		applySet(catKey, id, field, box.Text)
	end)

	return row
end

-- One entry panel: a title row (id + Delete) + a field row per field.
local function buildEntry(catKey: string, id: string, ContentAdmin: any, applySet, applyDelete, applySpawn): Instance
	local cat = ContentAdmin.CATEGORIES[catKey]
	local panel = make("Frame", {
		BackgroundColor3 = COL_PANEL,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		corner(8),
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local title = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 0 })
	title.Parent = panel

	local del = make("TextButton", {
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.new(1, -56, 0.5, -10),
		BackgroundColor3 = COL_FIELD,
		AutoButtonColor = true,
		Text = "Delete",
		TextColor3 = COL_DANGER,
		TextSize = 12,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	del.Parent = title
	del.MouseButton1Click:Connect(function()
		applyDelete(catKey, id)
	end)

	-- Gatherables get a one-click "Add to World" that drops a tagged, Resource-set Part in front of
	-- the camera (the no-code way to place a node) — the bridge between the editor and the world.
	local labelRight = 64
	if catKey == "Resources" and applySpawn then
		local add = make("TextButton", {
			Size = UDim2.fromOffset(104, 20),
			Position = UDim2.new(1, -168, 0.5, -10),
			BackgroundColor3 = COL_FIELD,
			AutoButtonColor = true,
			Text = "+ Add to World",
			TextColor3 = COL_ACCENT,
			TextSize = 11,
			Font = FONT,
			BorderSizePixel = 0,
		}, { corner(4) })
		add.Parent = title
		add.MouseButton1Click:Connect(function()
			applySpawn(id)
		end)
		labelRight = 176
	end

	make("TextLabel", {
		Size = UDim2.new(1, -labelRight, 1, 0),
		BackgroundTransparency = 1,
		Text = id,
		TextColor3 = COL_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
	}).Parent =
		title

	for i, field in cat.fields do
		local row = buildField(catKey, id, field, ContentAdmin.read(catKey, id, field), applySet)
		row.LayoutOrder = i
		row.Parent = panel
	end

	return panel
end

-- Build one category block: bold header, a create row, then an entry panel per id.
local function buildCategory(
	catKey: string,
	ContentAdmin: any,
	applySet,
	applyCreate,
	applyDelete,
	applySpawn
): Instance
	local cat = ContentAdmin.CATEGORIES[catKey]
	local block = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = cat.title,
		TextColor3 = COL_ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 0,
	}).Parent =
		block

	-- Create row: [ new id ............ ] [ + Create ]
	local createRow = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1 })
	createRow.Parent = block
	local idBox = make("TextBox", {
		Size = UDim2.new(1, -92, 1, 0),
		BackgroundColor3 = COL_FIELD,
		Text = "",
		PlaceholderText = cat.keyLabel,
		TextColor3 = COL_TEXT,
		TextSize = 13,
		Font = FONT,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, { corner(4), make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	idBox.Parent = createRow
	local createBtn = make("TextButton", {
		Size = UDim2.fromOffset(84, 28),
		Position = UDim2.new(1, -84, 0, 0),
		BackgroundColor3 = COL_FIELD,
		AutoButtonColor = true,
		Text = "+ Create",
		TextColor3 = COL_TEXT,
		TextSize = 13,
		Font = FONT,
		BorderSizePixel = 0,
	}, { corner(4) })
	createBtn.Parent = createRow
	createBtn.MouseButton1Click:Connect(function()
		applyCreate(catKey, idBox.Text)
	end)

	local ids = ContentAdmin.list(catKey)
	if #ids == 0 then
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = `No {string.lower(cat.title)} yet — create one above.`,
			TextColor3 = COL_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			Font = FONT,
			LayoutOrder = 2,
		}).Parent =
			block
	else
		for i, id in ids do
			local entry = buildEntry(catKey, id, ContentAdmin, applySet, applyDelete, applySpawn)
			entry.LayoutOrder = 2 + i
			entry.Parent = block
		end
	end

	return block
end

function ContentAdminUi.mount(
	container: Instance,
	ContentAdmin: any,
	applySet,
	applyCreate,
	applyDelete,
	applySpawn
): { refresh: () -> () }
	for _, child in container:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
	(container :: any).BackgroundColor3 = COL_BG

	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 })
	header.Parent = container
	make("TextLabel", {
		Size = UDim2.new(1, -84, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "Content",
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
		Size = UDim2.new(1, 0, 1, -32),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 12),
		}),
	})
	scroll.Parent = container

	local function refresh()
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIBase") then
				child:Destroy()
			end
		end
		for i, catKey in ContentAdmin.ORDER do
			local block = buildCategory(catKey, ContentAdmin, applySet, applyCreate, applyDelete, applySpawn)
			block.LayoutOrder = i
			block.Parent = scroll
		end
	end

	refreshBtn.MouseButton1Click:Connect(refresh)
	refresh()
	return { refresh = refresh }
end

return ContentAdminUi
