--[[
	Demo boot script. Shows both extension layers:
	  1. registering content from code, and
	  2. reacting to creator-owned components via hooks.

	Try it: serve `demo.project.json` into a place, add a Part to Workspace, tag it
	"Gatherable" (CollectionService), set attributes ItemId="reed", Yield=2, HP=3,
	then play and interact with it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivorCore = require(ReplicatedStorage:WaitForChild("SurvivorCore"))

-- 1. Programmatic content
SurvivorCore.Items.register({ id = "reed", name = "Reed", stack = 20 })
SurvivorCore.Items.register({ id = "reed_basket", name = "Reed Basket", stack = 1 })
SurvivorCore.Recipes.register({
	id = "reed_basket",
	station = "hand",
	ingredients = { { item = "reed", count = 5 } },
	output = { item = "reed_basket", count = 1 },
})

-- 2. React to creator-owned Gatherables
SurvivorCore.Hooks.on("gather:depleted", function(ctx)
	print(("[demo] %s fully gathered %s"):format(ctx.player.Name, tostring(ctx.values.ItemId)))
end)

-- 3. The HUD shows a "Credits" counter; the game owns that value. Seed a sample so it
--    renders in the demo (a real game sets player:SetAttribute("Credits", n) itself).
local Players = game:GetService("Players")
local function seedCredits(player: Player)
	player:SetAttribute("Credits", 250)
end
for _, player in Players:GetPlayers() do
	seedCredits(player)
end
Players.PlayerAdded:Connect(seedCredits)

SurvivorCore.start()
print("SurvivorCore demo booted — v" .. SurvivorCore.VERSION)
