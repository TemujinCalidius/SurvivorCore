--!nonstrict
--[[
	ToolEquip — server. The hotbar → physical Tool bridge.

	The hotbar tracks an active slot as data; this turns it into a real, held Roblox `Tool` so
	tool-swing harvesting (and later combat) can read `character:FindFirstChildOfClass("Tool")`.
	When the active hotbar item's def has a `toolType`, a Tool is equipped into the character with a
	`ToolType` attribute (what gatherable nodes match against); switching slots / unequipping / a
	non-tool clears it, and it re-equips on respawn.

	Content-free: the Tool VISUAL is cloned from a creator-supplied template under
	`ReplicatedStorage.SurvivorCoreContent.Tools` (a Tool named by item id); with no template a
	minimal default Tool+Handle is built. Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.ToolEquip is server-only — require it via SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local InventoryTypes = require(script.Parent.Parent.shared.InventoryTypes)

local ToolEquip = {}

local TOOL_MARKER = "_SurvivorCoreTool"
local started = false

local function findTemplate(itemId: string): Tool?
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	local tools = content and content:FindFirstChild("Tools")
	local tmpl = tools and tools:FindFirstChild(itemId)
	if tmpl and tmpl:IsA("Tool") then
		return tmpl
	end
	return nil
end

local function buildDefaultTool(name: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 3)
	handle.Parent = tool
	return tool
end

local function makeTool(def: any, itemId: string): Tool
	local tmpl = findTemplate(itemId)
	local tool = if tmpl then tmpl:Clone() else buildDefaultTool(def.name or itemId)
	if tmpl then
		-- A held Tool's parts must be unanchored to weld to the hand; creator templates authored in
		-- the world (e.g. the plugin's "+ Tool model") are often left anchored, so normalise here.
		for _, p in tool:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
			end
		end
	end
	tool.Name = def.name or itemId
	tool:SetAttribute(TOOL_MARKER, true)
	tool:SetAttribute("_ItemId", itemId)
	tool:SetAttribute("ToolType", def.toolType)
	-- If this item is a weapon, stamp the client-readable routing attributes (the client routes melee
	-- vs bow off WeaponKind, and sizes the bow draw meter off WeaponDrawTime). The SERVER re-reads the
	-- authoritative weapon stats from the Items registry — these are for client input only.
	if typeof(def.weaponKind) == "string" and def.weaponKind ~= "" then
		tool:SetAttribute("WeaponKind", def.weaponKind)
		tool:SetAttribute("WeaponDrawTime", tonumber(def.weaponDrawTime) or 0)
	end
	return tool
end

-- Remove any engine-spawned Tool the player currently holds (character or backpack).
local function clearEngineTool(player: Player)
	local places = { player.Character, player:FindFirstChildOfClass("Backpack") }
	for _, place in places do
		if place then
			for _, child in place:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(TOOL_MARKER) then
					child:Destroy()
				end
			end
		end
	end
end

local function currentEngineTool(player: Player): Tool?
	local char = player.Character
	if char then
		for _, child in char:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute(TOOL_MARKER) then
				return child :: Tool
			end
		end
	end
	return nil
end

-- Sync the held Tool to the active hotbar slot.
local function refresh(player: Player)
	local char = player.Character
	if not char or not char:FindFirstChildOfClass("Humanoid") then
		return
	end

	local slot = tonumber(player:GetAttribute(InventoryTypes.HOTBAR_EQUIPPED_ATTR))
	local itemId = ""
	if slot then
		itemId = tostring(player:GetAttribute(InventoryTypes.hotbarSlotAttr(slot)) or "")
	end
	local def = itemId ~= "" and Registries.Items.get(itemId) or nil
	local toolType = def and def.toolType

	-- Already holding the right tool? Leave it (avoids re-equip flicker on a re-press).
	local held = currentEngineTool(player)
	if toolType and held and held:GetAttribute("_ItemId") == itemId then
		return
	end

	clearEngineTool(player)
	if not toolType then
		return -- active slot isn't a tool; nothing to hold
	end

	local tool = makeTool(def, itemId)
	tool.Parent = char -- parenting a Tool to the character equips (holds) it
end

local function addPlayer(player: Player)
	player:GetAttributeChangedSignal(InventoryTypes.HOTBAR_EQUIPPED_ATTR):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refresh, player)
	end)
	if player.Character then
		task.defer(refresh, player)
	end
end

function ToolEquip.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
end

return ToolEquip
