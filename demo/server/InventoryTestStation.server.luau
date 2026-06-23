--!nonstrict
--[[
	DEMO ONLY — a row of pickup parts to exercise the inventory by hand.

	Each part has a ProximityPrompt (walk up, press E) that grants items to the triggering
	player via SurvivorCore.Inventory.add — a live demonstration of:
	  • weight + stack limits (add returns false when you're over capacity)
	  • auto-hotbar (tools / consumables auto-pin to the smallest free hotbar slot on pickup)

	Open the menu with Tab to watch the slots fill. This is demo scaffolding, not engine code.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

local PICKUPS = {
	{ label = "PICK UP  Stone Axe", item = "stone_axe", amount = 1, color = Color3.fromRGB(120, 130, 140) },
	{ label = "PICK UP  Berries x5", item = "berry", amount = 5, color = Color3.fromRGB(180, 70, 110) },
	{ label = "PICK UP  Reed x10", item = "reed", amount = 10, color = Color3.fromRGB(110, 160, 90) },
}

local function buildPickup(def: any, position: Vector3)
	local part = Instance.new("Part")
	part.Name = "InventoryPickup"
	part.Size = Vector3.new(3, 3, 3)
	part.Anchored = true
	part.Color = def.color
	part.Material = Enum.Material.SmoothPlastic
	part.Position = position
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 44)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.label
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = def.label
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if not (SurvivorCore.Inventory and typeof(SurvivorCore.Inventory.add) == "function") then
			warn("[SurvivorCore demo] inventory not ready — has SurvivorCore.start() run?")
			return
		end
		local ok = SurvivorCore.Inventory.add(player, def.item, def.amount)
		if not ok then
			print(("[demo] %s couldn't carry %s (full or over weight)"):format(player.Name, def.item))
		end
	end)
end

local BASE = Vector3.new(0, 4, 16) -- opposite side from the stat test stations
for i, def in PICKUPS do
	local x = (i - (#PICKUPS + 1) / 2) * 4
	buildPickup(def, BASE + Vector3.new(x, 0, 0))
end
