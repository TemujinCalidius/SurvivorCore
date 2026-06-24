--[[
	Demo boot script. Shows both extension layers:
	  1. registering content from code, and
	  2. reacting to creator-owned components via hooks.

	Try it: serve `demo.project.json` into a place, add a Part to Workspace, tag it
	"Gatherable" (CollectionService), set attributes ItemId="reed", Yield=2, HP=3,
	then play and interact with it — the reed lands in your inventory (press Tab).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

-- 1. Programmatic content -----------------------------------------------------
-- NOTE: the `icon` ids below are PLACEHOLDERS (the engine's stat icons) so the demo grid
-- isn't empty. A real game registers proper item icons (per-item `icon` or the "ItemIcons"
-- Assets category). The engine itself ships zero item content.
SurvivorCore.Items.register({
	id = "reed",
	name = "Reed",
	description = "A tough riverside stalk. Weave it into baskets and cordage.",
	stack = 20,
	weight = 0.05,
	category = "material",
	icon = "rbxassetid://102789813187589",
})
SurvivorCore.Items.register({
	id = "reed_basket",
	name = "Reed Basket",
	description = "A simple woven basket.",
	stack = 1,
	weight = 0.5,
	category = "container",
	icon = "rbxassetid://137051934393677",
})
SurvivorCore.Items.register({
	id = "berry",
	name = "Wild Berries",
	description = "A small handful of tart berries. Eases hunger and thirst a little.",
	stack = 20,
	weight = 0.05,
	category = "consumable",
	onConsume = { Hunger = -15, Thirst = -5 },
	icon = "rbxassetid://138699077112926",
})
SurvivorCore.Items.register({
	id = "mushroom",
	name = "Cave Mushroom",
	description = "Filling — but eating it raw might make you sick.",
	stack = 10,
	weight = 0.1,
	category = "consumable",
	onConsume = { Hunger = -10, Health = 5, Poison = 15 },
	icon = "rbxassetid://86406240258610",
})
SurvivorCore.Items.register({
	id = "water_skin",
	name = "Water Skin",
	description = "A full skin of water. Drink to quench your thirst.",
	stack = 1,
	weight = 0.5,
	category = "tool",
	onConsume = { Thirst = -40 },
	icon = "rbxassetid://124374881225649",
})
SurvivorCore.Items.register({
	id = "stone_axe",
	name = "Stone Axe",
	description = "A crude chopping tool. Equip it from the hotbar, then click a tree to chop.",
	stack = 1,
	weight = 1.5,
	category = "tool",
	toolType = "axe", -- the ToolEquip bridge gives the held Tool this ToolType; trees require "axe"
	icon = "rbxassetid://129856164091801",
})
SurvivorCore.Items.register({
	id = "wood",
	name = "Wood",
	description = "A length of timber chopped from a tree. Craft it into planks.",
	stack = 20,
	weight = 0.4,
	category = "material",
	icon = "rbxassetid://102789813187589",
})
SurvivorCore.Items.register({
	id = "plank",
	name = "Wooden Plank",
	description = "Milled from wood at hand. A basic building material.",
	stack = 20,
	weight = 0.3,
	category = "material",
	icon = "rbxassetid://137051934393677",
})

-- Gatherable RESOURCE defs: what a tagged node *is*. A creator tags a mesh "Gatherable" and sets
-- Resource = "<id>" to inherit these (no per-node attributes). HP>0 + a tool = click-to-swing;
-- no tool = bare-hand hold-E. (These can also be authored no-code via the admin plugin.)
SurvivorCore.Resources.register({
	id = "oak_tree",
	item = "wood",
	hp = 5,
	requireTool = "axe", -- needs an axe equipped
	yieldMin = 1,
	yieldMax = 2,
})
SurvivorCore.Resources.register({
	id = "reed_bush",
	item = "reed",
	hp = 3,
	requireTool = "", -- bare-hand
	yieldMin = 1,
	yieldMax = 2,
})
SurvivorCore.Items.register({
	id = "straw_hat",
	name = "Straw Hat",
	description = "Keeps the sun off. Equips to the head slot.",
	stack = 1,
	weight = 0.2,
	category = "apparel",
	equipment = { slot = "head" },
	icon = "rbxassetid://88514622686548",
})
SurvivorCore.Items.register({
	id = "reed_satchel",
	name = "Reed Satchel",
	description = "A woven back-satchel. Equip it for +6 slots and +10 kg of carry weight.",
	stack = 1,
	weight = 0.8,
	category = "container",
	equipment = { slot = "back" },
	backpack = { slots = 6, maxWeight = 10 },
	icon = "rbxassetid://137051934393677",
})

SurvivorCore.Recipes.register({
	id = "reed_basket",
	station = "hand",
	ingredients = { { item = "reed", count = 5 } },
	output = { item = "reed_basket", count = 1 },
})
SurvivorCore.Recipes.register({
	id = "plank",
	station = "hand",
	ingredients = { { item = "wood", count = 2 } },
	output = { item = "plank", count = 1 },
})

-- 2. React to creator-owned Gatherables (the engine grants the per-hit yield into the inventory).
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
	print(("[demo] %s fully gathered %s"):format(ctx.player.Name, tostring(ctx.resource or ctx.item)))
end)

-- A flourish hook: print whenever a consumable is used.
SurvivorCore.Hooks.on("item:use", function(ctx)
	print(("[demo] %s used %s"):format(ctx.player.Name, tostring(ctx.itemId)))
end)

-- 3. Seed sample player state so the HUD + inventory render populated in the demo.
--    A real game sets these itself (or restores them from a DataStore).
local function seedPlayer(player: Player)
	player:SetAttribute("Credits", 250)

	-- A starter inventory (slots 1-4 of the base 5; slot 5 left free to demo equip/unequip).
	player:SetAttribute("InvSlot_1", "berry")
	player:SetAttribute("InvQty_1", 12)
	player:SetAttribute("InvSlot_2", "mushroom")
	player:SetAttribute("InvQty_2", 3)
	player:SetAttribute("InvSlot_3", "water_skin")
	player:SetAttribute("InvQty_3", 1)
	player:SetAttribute("InvSlot_4", "reed_satchel")
	player:SetAttribute("InvQty_4", 1)
	player:SetAttribute("InvSlot_5", "stone_axe")
	player:SetAttribute("InvQty_5", 1)
	player:SetAttribute("HotbarSlot1", "berry") -- a pre-pinned quick slot
	player:SetAttribute("HotbarSlot2", "stone_axe") -- press 2 to equip the axe, then click a tree
	player:SetAttribute("EquipSlot_Head", "straw_hat") -- a pre-filled equipment slot
end
for _, player in Players:GetPlayers() do
	seedPlayer(player)
end
Players.PlayerAdded:Connect(seedPlayer)

SurvivorCore.start()

-- 4. The demo "gather field": a tool-gated tree + a bare-hand reed, the axe Tool template the
--    hotbar equips, and the reaction "juice" (reed sways on hit; the tree fells + leaves a stump).
--    All demo content — the engine ships none of it. Built after start() so the resource defs are
--    registered before the nodes bind.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- The axe Tool the ToolEquip bridge clones when "stone_axe" is the active hotbar item.
local function buildAxeTemplate()
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	if not content then
		content = Instance.new("Folder")
		content.Name = "SurvivorCoreContent"
		content.Parent = ReplicatedStorage
	end
	local tools = content:FindFirstChild("Tools")
	if not tools then
		tools = Instance.new("Folder")
		tools.Name = "Tools"
		tools.Parent = content
	end
	if tools:FindFirstChild("stone_axe") then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "stone_axe"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 3, 0.6)
	handle.Color = Color3.fromRGB(110, 80, 55)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	tool.Parent = tools
end
buildAxeTemplate()

local function buildTree(position: Vector3)
	local trunk = Instance.new("Part")
	trunk.Name = "OakTree"
	trunk.Anchored = true
	trunk.Size = Vector3.new(2, 14, 2)
	trunk.Position = position + Vector3.new(0, 7, 0)
	trunk.Color = Color3.fromRGB(95, 70, 45)
	trunk.Material = Enum.Material.Wood

	local leaves = Instance.new("Part")
	leaves.Name = "Leaves"
	leaves.Shape = Enum.PartType.Ball
	leaves.Size = Vector3.new(9, 9, 9)
	leaves.Position = position + Vector3.new(0, 15, 0)
	leaves.Color = Color3.fromRGB(70, 130, 70)
	leaves.Material = Enum.Material.Grass
	leaves.Anchored = false
	leaves.CanCollide = false
	leaves.Massless = true
	leaves.Parent = trunk
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = trunk
	weld.Part1 = leaves
	weld.Parent = trunk

	trunk:SetAttribute("Resource", "oak_tree")
	trunk:SetAttribute("DestroyOnDeplete", false) -- the fell reaction transforms it instead
	CollectionService:AddTag(trunk, "Gatherable")
	trunk.Parent = Workspace
end

local function buildReed(position: Vector3)
	local reed = Instance.new("Part")
	reed.Name = "ReedBush"
	reed.Anchored = true
	reed.Size = Vector3.new(2, 4, 2)
	reed.Position = position + Vector3.new(0, 2, 0)
	reed.Color = Color3.fromRGB(110, 160, 90)
	reed.Material = Enum.Material.Grass
	reed:SetAttribute("_Rest", reed.CFrame)
	reed:SetAttribute("Resource", "reed_bush")
	CollectionService:AddTag(reed, "Gatherable")
	reed.Parent = Workspace
end

buildTree(Vector3.new(10, 0, 28))
buildTree(Vector3.new(18, 0, 28))
buildReed(Vector3.new(-8, 0, 28))
buildReed(Vector3.new(-12, 0, 28))

-- Reaction juice (per resource type) — pure creator content via the engine's reaction API.
local SWAY = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
SurvivorCore.Gather.onReaction("reed_bush", "hit", function(ctx)
	local reed = ctx.instance
	if reed and reed:IsA("BasePart") then
		local rest = reed:GetAttribute("_Rest") or reed.CFrame
		TweenService:Create(reed, SWAY, { CFrame = rest * CFrame.Angles(0, 0, math.rad(15)) }):Play()
	end
end)
SurvivorCore.Gather.onReaction("oak_tree", "depleted", function(ctx)
	local trunk = ctx.instance
	if not trunk or not trunk:IsA("BasePart") then
		return
	end
	local stump = Instance.new("Part")
	stump.Name = "Stump"
	stump.Anchored = true
	stump.Size = Vector3.new(2.4, 1.2, 2.4)
	stump.Position = Vector3.new(trunk.Position.X, trunk.Position.Y - trunk.Size.Y / 2 + 0.6, trunk.Position.Z)
	stump.Color = Color3.fromRGB(95, 70, 45)
	stump.Material = Enum.Material.Wood
	stump.Parent = Workspace
	-- Let physics topple the trunk (leaves welded along for the ride), then clean up.
	trunk.Anchored = false
	trunk.AssemblyAngularVelocity = Vector3.new(0, 0, 6)
	task.delay(4, function()
		if trunk and trunk.Parent then
			trunk:Destroy()
		end
	end)
end)

print("SurvivorCore demo booted — v" .. SurvivorCore.VERSION)
