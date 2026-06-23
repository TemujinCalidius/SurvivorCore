--!nonstrict
--[[
	CharacterSheet — binds the Character tab. CLIENT-ONLY.

	Drives DATA only on two kinds of authored element (discovered by attribute, like the HUD):
	  • `EquipSlot` = <name> (head/top/pants/shoes/back/quiver) → its `Icon` + `Name` from the
	    EquipSlot_<Name> player attribute. Clicking an occupied slot fires InventoryUnequip.
	  • `AttributeReadout` = <attr> → its `Value` text from that player attribute (the seam for
	    showing attributes that equipment will later modify).

	Booted by SurvivorCore.startClient().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore.CharacterSheet is client-only")

local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)
local ItemData = require(script.Parent.Parent.shared.ItemData)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local SlotGrid = require(script.Parent.SlotGrid)

local CharacterSheet = {}

local started = false
local localPlayer = Players.LocalPlayer

local function bindEquipSlot(element: GuiObject)
	local slotName = element:GetAttribute("EquipSlot")
	if typeof(slotName) ~= "string" or slotName == "" then
		return
	end
	local attr = InventoryTypes.equipSlotAttr(slotName)
	local icon = element:FindFirstChild("Icon")
	local nameLabel = element:FindFirstChild("Name")

	local function render()
		local itemId = tostring(localPlayer:GetAttribute(attr) or "")
		local def = if itemId ~= "" then ItemData.get(itemId) else nil
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			local id = if itemId ~= "" then SlotGrid.resolveItemIcon(itemId) else ""
			icon.Image = id
			icon.Visible = id ~= ""
		end
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = if def then def.name else ""
		end
	end

	-- Click an occupied slot to unequip it back to inventory.
	element.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if tostring(localPlayer:GetAttribute(attr) or "") ~= "" then
				Remotes.event("InventoryUnequip"):FireServer(slotName)
			end
		end
	end)

	localPlayer:GetAttributeChangedSignal(attr):Connect(render)
	render()
end

local function bindAttributeReadout(element: GuiObject)
	local attrName = element:GetAttribute("AttributeReadout")
	if typeof(attrName) ~= "string" or attrName == "" then
		return
	end
	local valueLabel = element:FindFirstChild("Value")
	if not (valueLabel and valueLabel:IsA("TextLabel")) then
		return
	end

	local function render()
		local v = localPlayer:GetAttribute(attrName)
		valueLabel.Text = if typeof(v) == "number" then tostring(math.floor(v + 0.5)) else "—"
	end

	localPlayer:GetAttributeChangedSignal(attrName):Connect(render)
	render()
end

function CharacterSheet.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local bound: { [Instance]: boolean } = {}

	local function tryBind(d: Instance)
		if bound[d] or not d:IsA("GuiObject") then
			return
		end
		if d:GetAttribute("EquipSlot") ~= nil then
			bound[d] = true
			bindEquipSlot(d)
		elseif d:GetAttribute("AttributeReadout") ~= nil then
			bound[d] = true
			bindAttributeReadout(d)
		end
	end

	for _, d in playerGui:GetDescendants() do
		tryBind(d)
	end
	playerGui.DescendantAdded:Connect(tryBind)
end

return CharacterSheet
