--!nonstrict
--[[
	InventoryUi — binds the Inventory tab. CLIENT-ONLY.

	Discovers the authored elements by attribute (like the HUD binder) and drives DATA only:
	  • `InventoryGrid` → a SlotGrid (clones slots, shows icons/counts, drag + select)
	  • `WeightReadout` → a Fill bar + Value text from CarryWeight / MaxCarryWeight
	  • `SlotReadout`   → "used / max slots"
	  • `ItemDetail`    → the selected item's icon/name/description + action buttons
	    (`Action` = use/equip/hotbar/split) that fire the inventory RemoteEvents.

	Drag drops are routed through DragDrop targets: inventory→inventory swaps fire
	InventorySwapSlots; inventory→hotbar pins fire InventorySetHotbar (registered by Hotbar).

	Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.InventoryUi is client-only")

local InventoryConfig = require(script.Parent.Parent.shared.InventoryConfig)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local ItemData = require(script.Parent.Parent.shared.ItemData)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local UiConfig = require(script.Parent.Parent.shared.UiConfig)
local DragDrop = require(script.Parent.DragDrop)
local SlotGrid = require(script.Parent.SlotGrid)

local InventoryUi = {}

local started = false
local localPlayer = Players.LocalPlayer

local function findByAttr(root: Instance, attr: string): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d:GetAttribute(attr) ~= nil then
			return d
		end
	end
	return nil
end

local function readNum(attr: string): number
	local v = localPlayer:GetAttribute(attr)
	return if typeof(v) == "number" then v else 0
end

local function clientFindFreeHotbar(): number?
	local size = math.floor(tonumber(InventoryConfig.get().HotbarSize) or 9)
	for n = 1, size do
		local v = localPlayer:GetAttribute(InventoryTypes.hotbarSlotAttr(n))
		if typeof(v) ~= "string" or v == "" then
			return n
		end
	end
	return nil
end

local function bindGrid(grid: GuiObject)
	local menu = grid:FindFirstAncestorWhichIsA("ScreenGui") or grid
	local theme = UiConfig.get().Theme

	-- Detail strip + selection ------------------------------------------------
	local detail = findByAttr(menu, "ItemDetail")
	local detailIcon, detailName, detailDesc
	local actions: { [string]: GuiButton } = {}
	if detail then
		detailIcon = detail:FindFirstChild("Icon")
		detailName = detail:FindFirstChild("Name")
		detailDesc = detail:FindFirstChild("Description")
		for _, d in detail:GetDescendants() do
			local action = d:GetAttribute("Action")
			if typeof(action) == "string" and d:IsA("GuiButton") then
				actions[action] = d
			end
		end
	end

	local selectedSlot: number? = nil

	local function renderDetail()
		if not detail then
			return
		end
		local itemId = if selectedSlot
			then tostring(localPlayer:GetAttribute(InventoryTypes.invSlotAttr(selectedSlot)) or "")
			else ""
		local def = if itemId ~= "" then ItemData.get(itemId) else nil
		local qty = if selectedSlot then readNum(InventoryTypes.invQtyAttr(selectedSlot)) else 0

		if detailIcon and (detailIcon:IsA("ImageLabel") or detailIcon:IsA("ImageButton")) then
			local id = if itemId ~= "" then SlotGrid.resolveItemIcon(itemId) else ""
			detailIcon.Image = id
			detailIcon.Visible = id ~= ""
		end
		if detailName and detailName:IsA("TextLabel") then
			detailName.Text = if def then def.name else ""
		end
		if detailDesc and detailDesc:IsA("TextLabel") then
			detailDesc.Text = if def and def.description then def.description else ""
		end
		-- Show actions only when they apply to the selected item.
		if actions.use then
			actions.use.Visible = def ~= nil and def.consumable == true
		end
		if actions.equip then
			actions.equip.Visible = def ~= nil and def.equipSlot ~= nil
		end
		if actions.hotbar then
			actions.hotbar.Visible = def ~= nil
		end
		if actions.split then
			actions.split.Visible = def ~= nil and qty > 1
		end
	end

	-- Mount the slot grid; selecting a slot refreshes the detail strip.
	SlotGrid.mount(grid, DragDrop, {
		onSelect = function(slot)
			selectedSlot = slot
			renderDetail()
		end,
	})

	-- Wire the action buttons (once).
	if actions.use then
		actions.use.Activated:Connect(function()
			if selectedSlot then
				Remotes.event("InventoryUseItem"):FireServer(selectedSlot)
			end
		end)
	end
	if actions.equip then
		actions.equip.Activated:Connect(function()
			if selectedSlot then
				Remotes.event("InventoryEquip"):FireServer(selectedSlot)
			end
		end)
	end
	if actions.hotbar then
		actions.hotbar.Activated:Connect(function()
			if not selectedSlot then
				return
			end
			local itemId = tostring(localPlayer:GetAttribute(InventoryTypes.invSlotAttr(selectedSlot)) or "")
			local free = clientFindFreeHotbar()
			if itemId ~= "" and free then
				Remotes.event("InventorySetHotbar"):FireServer(free, itemId)
			end
		end)
	end
	if actions.split then
		actions.split.Activated:Connect(function()
			if not selectedSlot then
				return
			end
			local qty = readNum(InventoryTypes.invQtyAttr(selectedSlot))
			if qty > 1 then
				Remotes.event("InventorySplitStack"):FireServer(selectedSlot, math.floor(qty / 2))
			end
		end)
	end

	-- Weight readout ----------------------------------------------------------
	local weight = findByAttr(menu, "WeightReadout")
	local weightFill = weight and weight:FindFirstChild("Fill")
	local weightValue = weight and weight:FindFirstChild("Value")
	local function renderWeight()
		local carry = readNum(InventoryTypes.CARRY_WEIGHT_ATTR)
		local maxCarry = readNum(InventoryTypes.MAX_CARRY_WEIGHT_ATTR)
		local ratio = if maxCarry > 0 then carry / maxCarry else 0
		if weightFill and weightFill:IsA("GuiObject") then
			local s = weightFill.Size
			weightFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, s.Y.Scale, s.Y.Offset)
			weightFill.BackgroundColor3 = if ratio > 1 then theme.Bad else theme.Ok
		end
		if weightValue and weightValue:IsA("TextLabel") then
			weightValue.Text = string.format("%.1f / %.0f kg", carry, maxCarry)
		end
	end

	-- Slot-usage readout ------------------------------------------------------
	local slotReadout = findByAttr(menu, "SlotReadout")
	local slotValue = slotReadout and slotReadout:FindFirstChild("Value")
	local function renderSlots()
		if not (slotValue and slotValue:IsA("TextLabel")) then
			return
		end
		local max = math.floor(readNum(InventoryTypes.MAX_SLOTS_ATTR))
		local used = 0
		for n = 1, max do
			if tostring(localPlayer:GetAttribute(InventoryTypes.invSlotAttr(n)) or "") ~= "" then
				used += 1
			end
		end
		slotValue.Text = string.format("%d / %d slots", used, max)
	end

	-- React to replicated changes.
	localPlayer.AttributeChanged:Connect(function(attr)
		if attr == InventoryTypes.CARRY_WEIGHT_ATTR or attr == InventoryTypes.MAX_CARRY_WEIGHT_ATTR then
			renderWeight()
		end
		if string.match(attr, "^InvSlot_(%d+)$") or attr == InventoryTypes.MAX_SLOTS_ATTR then
			renderSlots()
		end
		-- Keep the detail strip honest when the selected slot's contents change.
		if selectedSlot then
			local n = string.match(attr, "^Inv%a-_(%d+)$")
			if n and tonumber(n) == selectedSlot then
				renderDetail()
			end
		end
	end)

	-- Inventory→inventory drop target: drop one slot onto another → swap/merge.
	local function slotAt(pos: Vector2): number?
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("Index") ~= nil and DragDrop.hitTestGui(child, pos) then
				return child:GetAttribute("Index")
			end
		end
		return nil
	end
	DragDrop.addTarget({
		hitTest = function(pos)
			return slotAt(pos) ~= nil
		end,
		onDrop = function(payload, pos)
			local target = slotAt(pos)
			if not target then
				return
			end
			if payload.kind == "invSlot" and payload.slot ~= target then
				Remotes.event("InventorySwapSlots"):FireServer(payload.slot, target)
			end
		end,
	})

	renderWeight()
	renderSlots()
	renderDetail()
end

function InventoryUi.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local bound = false
	local function tryBind()
		if bound then
			return
		end
		local grid = findByAttr(playerGui, "InventoryGrid")
		if grid then
			bound = true
			bindGrid(grid)
		end
	end

	tryBind()
	playerGui.DescendantAdded:Connect(function(d)
		if d:IsA("GuiObject") and d:GetAttribute("InventoryGrid") ~= nil then
			tryBind()
		end
	end)
end

return InventoryUi
