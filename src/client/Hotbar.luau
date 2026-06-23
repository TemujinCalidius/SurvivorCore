--!nonstrict
--[[
	Hotbar — binds the bottom quick-use hotbar. CLIENT-ONLY.

	Discovers the authored `HotbarSlot` = 1..9 frames and drives DATA only — each slot's `Icon`
	(the pinned item), `Count` (its inventory qty), `Key` (the digit), and `Active` highlight
	(visible when HotbarEquippedSlot == n). Input:
	  • number keys 1-9, or clicking a slot → InventoryUseHotbar(n)  (use the pinned item)
	  • drag a slot onto another → InventorySwapHotbar (reorder)
	  • right-click a slot → InventorySetHotbar(n, nil) (unpin)
	  • an inventory item dropped on a slot → InventorySetHotbar(n, itemId) (pin)

	Also disables Roblox's built-in CoreGui Backpack so the default hotbar doesn't double up
	(mirrors how the HUD disables the built-in Health GUI).

	Booted by SurvivorCore.startClient(). Tuning: "UI" + "Inventory" config sections.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

assert(RunService:IsClient(), "SurvivorCore.Hotbar is client-only")

local InventoryConfig = require(script.Parent.Parent.shared.InventoryConfig)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local DragDrop = require(script.Parent.DragDrop)
local SlotGrid = require(script.Parent.SlotGrid)

local Hotbar = {}

local started = false
local localPlayer = Players.LocalPlayer

-- KeyCodes One..Nine map to hotbar slots 1..9.
local DIGIT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local function totalQty(itemId: string): number
	if itemId == "" then
		return 0
	end
	local max = math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.MAX_SLOTS_ATTR)) or 0)
	local total = 0
	for n = 1, max do
		if tostring(localPlayer:GetAttribute(InventoryTypes.invSlotAttr(n)) or "") == itemId then
			total += math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.invQtyAttr(n))) or 0)
		end
	end
	return total
end

local function disableCoreBackpack()
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				break
			end
			task.wait(0.2)
		end
	end)
end

local function bindHotbar(root: Instance)
	local slots: { [number]: GuiObject } = {}

	local function driveSlot(n: number)
		local slot = slots[n]
		if not slot then
			return
		end
		local itemId = tostring(localPlayer:GetAttribute(InventoryTypes.hotbarSlotAttr(n)) or "")
		local active = math.floor(tonumber(localPlayer:GetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR)) or 0)

		local icon = slot:FindFirstChild("Icon")
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			local id = if itemId ~= "" then SlotGrid.resolveItemIcon(itemId) else ""
			icon.Image = id
			icon.Visible = id ~= ""
		end
		local count = slot:FindFirstChild("Count")
		if count and count:IsA("TextLabel") then
			local qty = totalQty(itemId)
			count.Text = if qty > 1 then tostring(qty) else ""
			count.Visible = qty > 1
		end
		local activeFrame = slot:FindFirstChild("Active")
		if activeFrame and activeFrame:IsA("GuiObject") then
			activeFrame.Visible = active == n and itemId ~= ""
		end
	end

	local function refresh()
		for n in slots do
			driveSlot(n)
		end
	end

	-- Discover the 1..9 slot frames.
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			local n = d:GetAttribute("HotbarSlot")
			if typeof(n) == "number" then
				slots[math.floor(n)] = d
			end
		end
	end

	for n, slot in slots do
		slot.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Right-click → unpin.
				Remotes.event("InventorySetHotbar"):FireServer(n, nil)
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local itemId = tostring(localPlayer:GetAttribute(InventoryTypes.hotbarSlotAttr(n)) or "")
				if itemId ~= "" then
					DragDrop.beginDrag({
						kind = "hotbarSlot",
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
				if DragDrop.didDrag() then
					return -- the press was a drag (reorder), not a click
				end
				Remotes.event("InventoryUseHotbar"):FireServer(n)
			end)
		end
	end

	-- React to replicated changes.
	localPlayer.AttributeChanged:Connect(function(attr)
		-- Pinned items, the active slot, and inventory qty (the Count badge) all drive the hotbar.
		if
			string.match(attr, "^HotbarSlot%d+$")
			or attr == InventoryTypes.HOTBAR_EQUIPPED_ATTR
			or string.match(attr, "^InvSlot_%d+$")
			or string.match(attr, "^InvQty_%d+$")
		then
			refresh()
		end
	end)

	-- Drop target: an inventory item pins here; a hotbar item reorders here.
	local function hotbarSlotAt(pos: Vector2): number?
		for n, frame in slots do
			if DragDrop.hitTestGui(frame, pos) then
				return n
			end
		end
		return nil
	end
	DragDrop.addTarget({
		hitTest = function(pos)
			return hotbarSlotAt(pos) ~= nil
		end,
		onDrop = function(payload, pos)
			local target = hotbarSlotAt(pos)
			if not target then
				return
			end
			if payload.kind == "invSlot" then
				Remotes.event("InventorySetHotbar"):FireServer(target, payload.itemId)
			elseif payload.kind == "hotbarSlot" and payload.slot ~= target then
				Remotes.event("InventorySwapHotbar"):FireServer(payload.slot, target)
			end
		end,
	})

	-- Number keys 1-9 → use that hotbar slot.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local n = DIGIT_KEYS[input.KeyCode]
		if n and n <= (math.floor(tonumber(InventoryConfig.get().HotbarSize) or 9)) then
			Remotes.event("InventoryUseHotbar"):FireServer(n)
		end
	end)

	refresh()
end

function Hotbar.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	disableCoreBackpack()

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local bound = false
	local function tryBind()
		if bound then
			return
		end
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Name == "SurvivalHotbar" then
				bound = true
				bindHotbar(gui)
				return
			end
		end
	end

	tryBind()
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "SurvivalHotbar" and child:IsA("ScreenGui") then
			tryBind()
		end
	end)
end

return Hotbar
