--!nonstrict
--[[
	SlotGrid — the reusable inventory slot-grid binder primitive. CLIENT-ONLY.

	Given a container marked `InventoryGrid` that holds one prototype child marked `SlotTemplate`,
	this clones the template `MaxInvSlots` times into the grid (the grid's authored UIGridLayout
	does the layout) and drives each slot's data ONLY — never its styling:
	  • child ImageLabel `Icon`  → item icon (hidden when "")
	  • child TextLabel  `Count` → stack qty (hidden when ≤ 1)
	  • child GuiObject  `Selected` → shown for the selected slot
	Each slot is a drag source (press-drag past threshold → DragDrop ghost) and click-to-select.

	Rebinds reactively to InvSlot_N / InvQty_N / MaxInvSlots attribute changes (same model as the
	HUD binder). Also exposes the shared icon resolver used by the hotbar / character sheet.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.SlotGrid is client-only")

local Assets = require(script.Parent.Parent.foundation.Assets)
local ItemData = require(script.Parent.Parent.shared.ItemData)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)

local SlotGrid = {}

local ICON_CATEGORY = "ItemIcons"
local localPlayer = Players.LocalPlayer

-- Resolve an item's icon: replicated def icon → Assets registry ("ItemIcons") → "" (hidden).
-- Mirrors Hud.resolveIcon, so a fresh engine shows clean empty slots, never a broken image.
function SlotGrid.resolveItemIcon(itemId: string): string
	local def = ItemData.get(itemId)
	if def and typeof(def.icon) == "string" and def.icon ~= "" then
		return def.icon
	end
	return Assets.tryGet(ICON_CATEGORY, itemId)
end

-- A short uppercase tag for an item (drag-ghost / empty-icon fallback).
function SlotGrid.abbrev(itemId: string): string
	local def = ItemData.get(itemId)
	local name = (def and def.name) or itemId
	return string.upper(string.sub(name, 1, 3))
end

local function readSlotItemId(n: number): string
	local v = localPlayer:GetAttribute(InventoryTypes.invSlotAttr(n))
	return if typeof(v) == "string" then v else ""
end

local function readSlotQty(n: number): number
	local v = localPlayer:GetAttribute(InventoryTypes.invQtyAttr(n))
	return if typeof(v) == "number" then math.floor(v) else 0
end

local function readMaxSlots(): number
	local v = localPlayer:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR)
	return if typeof(v) == "number" and v >= 1 then math.floor(v) else 0
end

-- Mount the grid in `container`. opts.onSelect(slot, itemId) fires on a click (not a drag).
-- Requires the DragDrop module (passed in so SlotGrid doesn't hard-depend on drop wiring).
function SlotGrid.mount(container: GuiObject, dragDrop: any, opts: any)
	opts = opts or {}
	local template = container:FindFirstChild("SlotTemplate", true)
	for _, d in container:GetDescendants() do
		if d:IsA("GuiObject") and d:GetAttribute("SlotTemplate") ~= nil then
			template = d
			break
		end
	end
	if not template or not template:IsA("GuiObject") then
		warn(`[SurvivorCore SlotGrid] '{container:GetFullName()}' has no SlotTemplate child`)
		return nil
	end
	template.Visible = false

	local slots: { [number]: GuiObject } = {}
	local selected: number? = nil

	local function driveSlot(n: number)
		local slot = slots[n]
		if not slot then
			return
		end
		local itemId = readSlotItemId(n)
		local qty = readSlotQty(n)

		local icon = slot:FindFirstChild("Icon")
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			local id = if itemId ~= "" then SlotGrid.resolveItemIcon(itemId) else ""
			icon.Image = id
			icon.Visible = id ~= ""
		end
		local count = slot:FindFirstChild("Count")
		if count and count:IsA("TextLabel") then
			count.Text = if qty > 1 then tostring(qty) else ""
			count.Visible = qty > 1
		end
		local sel = slot:FindFirstChild("Selected")
		if sel and sel:IsA("GuiObject") then
			sel.Visible = selected == n
		end
	end

	local function refresh()
		for n in slots do
			driveSlot(n)
		end
	end

	local function setSelected(n: number?)
		selected = n
		refresh()
	end

	local function wireSlot(n: number, slot: GuiObject)
		slot:SetAttribute("Index", n)
		slot.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local itemId = readSlotItemId(n)
				if itemId ~= "" then
					dragDrop.beginDrag({
						kind = "invSlot",
						slot = n,
						itemId = itemId,
						icon = SlotGrid.resolveItemIcon(itemId),
						label = SlotGrid.abbrev(itemId),
					})
				end
			end
		end)
		if slot:IsA("GuiButton") then
			slot.Activated:Connect(function()
				if dragDrop.didDrag() then
					return -- the press was a drag, not a click
				end
				setSelected(n)
				if opts.onSelect then
					opts.onSelect(n, readSlotItemId(n))
				end
			end)
		end
	end

	local function build()
		local max = readMaxSlots()
		-- Add missing slot clones.
		for n = 1, max do
			if not slots[n] then
				local clone = template:Clone()
				clone.Name = "Slot" .. n
				clone.Visible = true
				clone.LayoutOrder = n
				clone.Parent = container
				slots[n] = clone
				wireSlot(n, clone)
			end
		end
		-- Remove surplus slots (e.g. a backpack was unequipped).
		for n, slot in slots do
			if n > max then
				slot:Destroy()
				slots[n] = nil
			end
		end
		if selected and not slots[selected] then
			selected = nil
		end
		refresh()
	end

	build()

	localPlayer.AttributeChanged:Connect(function(attr)
		local slotIdx = string.match(attr, "^InvSlot_(%d+)$") or string.match(attr, "^InvQty_(%d+)$")
		local n = slotIdx and tonumber(slotIdx)
		if n then
			driveSlot(n)
		elseif attr == InventoryTypes.MAX_SLOTS_ATTR then
			build()
		end
	end)

	return {
		refresh = refresh,
		setSelected = setSelected,
		getSelected = function()
			return selected
		end,
		getSelectedItemId = function()
			return if selected then readSlotItemId(selected) else ""
		end,
	}
end

return SlotGrid
