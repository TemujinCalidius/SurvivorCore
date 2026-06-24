--!nonstrict
--[[
	CraftingUi — the Crafting tab. CLIENT-ONLY.

	Registers a "Crafting" panel via the engine's own SurvivorCore.UI.registerPanel API (which
	clones a styled tab button + a content frame), then fills it with one row per hand recipe
	(RecipeData.forStation("hand")): output icon + name, an ingredients line, and a Craft button
	that fires the CraftRecipe remote. Rows are gated live — greyed when the player lacks the
	ingredients — by reading the replicated inventory attributes (re-checked on every InvSlot_/
	InvQty_ change, same model as the slot grid). Themed from the "UI" Config section.

	Booted by SurvivorCore.startClient() (after PanelManager, so SurvivorCore.UI exists).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.CraftingUi is client-only")

local ItemData = require(script.Parent.Parent.shared.ItemData)
local RecipeData = require(script.Parent.Parent.shared.RecipeData)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local PanelManager = require(script.Parent.PanelManager)
local SlotGrid = require(script.Parent.SlotGrid)

local CraftingUi = {}

local started = false
local localPlayer = Players.LocalPlayer

local function clientQty(itemId: string): number
	local total = 0
	local max = math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR)) or 0)
	for n = 1, max do
		if tostring(localPlayer:GetAttribute(InventoryTypes.invSlotAttr(n)) or "") == itemId then
			total += math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.invQtyAttr(n))) or 0)
		end
	end
	return total
end

local function canCraftClient(recipe: any): boolean
	for _, ing in recipe.ingredients do
		if clientQty(ing.item) < ing.count then
			return false
		end
	end
	return true
end

local function itemName(itemId: string): string
	local def = ItemData.get(itemId)
	return (def and def.name) or itemId
end

local function ingredientsText(recipe: any): string
	local parts = {}
	for _, ing in recipe.ingredients do
		table.insert(parts, `{ing.count}× {itemName(ing.item)}`)
	end
	return table.concat(parts, ", ")
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildCrafting(content: Instance)
	local theme = UiConfig.get().Theme

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CraftList"
	scroll:SetAttribute("CraftList", true)
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Active = true -- sink clicks so the menu's click-outside overlay doesn't close the menu
	scroll.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local rows: { { recipe: any, btn: TextButton, name: TextLabel, ing: TextLabel, icon: ImageLabel } } = {}

	local function makeRow(recipe: any, order: number)
		local row = Instance.new("Frame")
		row.Name = "Recipe_" .. recipe.id
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = theme.SlotColor or theme.PanelColor or Color3.fromRGB(30, 34, 44)
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = scroll
		corner(row, theme.CornerRadius or 8)

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(40, 40)
		icon.Position = UDim2.fromOffset(8, 6)
		local outItem = recipe.output and recipe.output.item
		local iconId = if outItem then SlotGrid.resolveItemIcon(outItem) else ""
		icon.Image = iconId
		icon.Visible = iconId ~= ""
		icon.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, -160, 0, 22)
		nameLabel.Position = UDim2.fromOffset(56, 6)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Font = theme.FontBold or Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextColor3 = theme.Text or Color3.fromRGB(245, 245, 245)
		local outCount = (recipe.output and recipe.output.count) or 1
		nameLabel.Text = if outItem
			then (if outCount > 1 then `{itemName(outItem)} ×{outCount}` else itemName(outItem))
			else recipe.id
		nameLabel.Parent = row

		local ing = Instance.new("TextLabel")
		ing.Name = "Ingredients"
		ing.BackgroundTransparency = 1
		ing.Size = UDim2.new(1, -160, 0, 18)
		ing.Position = UDim2.fromOffset(56, 28)
		ing.TextXAlignment = Enum.TextXAlignment.Left
		ing.Font = theme.Font or Enum.Font.Gotham
		ing.TextSize = 12
		ing.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
		ing.Text = ingredientsText(recipe)
		ing.Parent = row

		local btn = Instance.new("TextButton")
		btn.Name = "Craft"
		btn:SetAttribute("Action", "craft")
		btn.Size = UDim2.fromOffset(84, 32)
		btn.Position = UDim2.new(1, -92, 0.5, -16)
		btn.Font = theme.FontBold or Enum.Font.GothamBold
		btn.TextSize = 14
		btn.Text = "Craft"
		btn.TextColor3 = theme.Text or Color3.fromRGB(245, 245, 245)
		btn.BackgroundColor3 = theme.Accent or Color3.fromRGB(160, 130, 80)
		btn.AutoButtonColor = true
		btn.Parent = row
		corner(btn, 6)
		btn.Activated:Connect(function()
			Remotes.event("CraftRecipe"):FireServer(recipe.id)
		end)

		table.insert(rows, { recipe = recipe, btn = btn, name = nameLabel, ing = ing, icon = icon })
	end

	local function refreshGating()
		for _, r in rows do
			local ok = canCraftClient(r.recipe)
			r.btn.Active = ok
			r.btn.AutoButtonColor = ok
			r.btn.BackgroundColor3 = if ok
				then (theme.Accent or Color3.fromRGB(160, 130, 80))
				else Color3.fromRGB(60, 64, 74)
			r.btn.Text = if ok then "Craft" else "Need more"
			-- Dim (but keep readable) the row when you can't afford it — no text-hiding overlay.
			local t = if ok then 0 else 0.45
			r.name.TextTransparency = t
			r.ing.TextTransparency = t
			r.icon.ImageTransparency = t
		end
	end

	local recipes = RecipeData.forStation("hand")
	for i, recipe in recipes do
		makeRow(recipe, i)
	end
	if #recipes == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Font = theme.Font or Enum.Font.Gotham
		empty.TextSize = 14
		empty.TextColor3 = theme.TextSecondary or Color3.fromRGB(200, 205, 215)
		empty.Text = "No hand recipes registered."
		empty.Parent = scroll
	end

	refreshGating()
	localPlayer.AttributeChanged:Connect(function(attr)
		if
			string.match(attr, "^InvSlot_%d+$")
			or string.match(attr, "^InvQty_%d+$")
			or attr == InventoryTypes.MAX_SLOTS_ATTR
		then
			refreshGating()
		end
	end)
end

function CraftingUi.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	PanelManager.registerPanel({
		id = "crafting",
		title = "Crafting",
		order = 3,
		build = buildCrafting,
	})
end

return CraftingUi
