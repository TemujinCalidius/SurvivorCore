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
	description = "A crude chopping tool. Pick one up to see it auto-assign to your hotbar.",
	stack = 1,
	weight = 1.5,
	category = "tool",
	icon = "rbxassetid://129856164091801",
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

-- 2. React to creator-owned Gatherables (the engine also grants the Yield into the inventory)
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
	print(("[demo] %s fully gathered %s"):format(ctx.player.Name, tostring(ctx.values.ItemId)))
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
	player:SetAttribute("HotbarSlot1", "berry") -- a pre-pinned quick slot
	player:SetAttribute("EquipSlot_Head", "straw_hat") -- a pre-filled equipment slot
end
for _, player in Players:GetPlayers() do
	seedPlayer(player)
end
Players.PlayerAdded:Connect(seedPlayer)

SurvivorCore.start()
print("SurvivorCore demo booted — v" .. SurvivorCore.VERSION)
