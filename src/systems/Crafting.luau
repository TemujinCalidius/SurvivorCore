--!nonstrict
--[[
	Crafting — server. Hand crafting runtime (issue #4): validate a recipe's ingredients against the
	player's inventory, consume them, and produce the output — closing gather → craft → use.
	Server-authoritative; station-agnostic (routes by `recipe.station`, "hand" first). Player-driven
	crafts CHANNEL for a time that scales with the recipe's complexity, showing a progress bar above
	the crafter (server-built, so everyone sees it). Emits craft:start / craft:end / craft:blocked.

	Public (SurvivorCore.Crafting): canCraft(player, recipeId) -> (bool, reason?), craft(...) (the
	INSTANT consume→produce, for code/tests), and craftTime(recipe).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

assert(RunService:IsServer(), "SurvivorCore.Crafting is server-only — require it via SurvivorCore.start()")

local Inventory = require(script.Parent.Inventory)
local Registries = require(script.Parent.Parent.registries)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local RecipeData = require(script.Parent.Parent.shared.RecipeData)
local CraftingConfig = require(script.Parent.Parent.shared.CraftingConfig)

local Recipes = Registries.Recipes

local Crafting = {}

local started = false
local channeling: { [Player]: boolean } = {} -- players mid-craft (re-entry guard)

local function ingredientsOf(recipe: any): { { item: string, count: number } }
	local out = {}
	if typeof(recipe.ingredients) == "table" then
		for _, ing in recipe.ingredients do
			if typeof(ing) == "table" and typeof(ing.item) == "string" then
				table.insert(out, { item = ing.item, count = math.max(1, math.floor(tonumber(ing.count) or 1)) })
			end
		end
	end
	return out
end

-- Channel time for a recipe: explicit `craftTime`, else BaseCraftTime + TimePerIngredient × units.
function Crafting.craftTime(recipe: any): number
	if typeof(recipe.craftTime) == "number" then
		return math.max(0, recipe.craftTime)
	end
	local cfg = CraftingConfig.get()
	local units = 0
	for _, ing in ingredientsOf(recipe) do
		units += ing.count
	end
	local t = (tonumber(cfg.BaseCraftTime) or 0.6) + (tonumber(cfg.TimePerIngredient) or 0.5) * units
	return math.clamp(t, 0, tonumber(cfg.MaxCraftTime) or 8)
end

-- True if the player can craft this recipe right now (hand station + has all ingredients).
function Crafting.canCraft(player: Player, recipeId: string): (boolean, string?)
	local recipe = Recipes.get(recipeId)
	if not recipe then
		return false, "unknown"
	end
	if recipe.station ~= nil and recipe.station ~= "hand" then
		return false, "station"
	end
	for _, ing in ingredientsOf(recipe) do
		if not Inventory.has(player, ing.item, ing.count) then
			return false, "ingredients"
		end
	end
	return true
end

-- Consume ingredients → produce output, refunding on any mid-way failure. No hooks (callers fire).
local function consumeProduce(player: Player, recipe: any): (boolean, string?)
	local consumed: { { item: string, count: number } } = {}
	local function refund()
		for _, c in consumed do
			Inventory.add(player, c.item, c.count)
		end
	end
	for _, ing in ingredientsOf(recipe) do
		if Inventory.remove(player, ing.item, ing.count) then
			table.insert(consumed, ing)
		else
			refund()
			return false, "ingredients"
		end
	end
	local output = recipe.output
	if output and typeof(output.item) == "string" then
		local count = math.max(1, math.floor(tonumber(output.count) or 1))
		if not Inventory.add(player, output.item, count) then
			refund() -- no room for the output: put the ingredients back, nothing lost
			return false, "full"
		end
	end
	return true, nil
end

-- INSTANT craft (public API for code/tests): validate → consume → produce, with hooks.
function Crafting.craft(player: Player, recipeId: string): boolean
	local ok, reason = Crafting.canCraft(player, recipeId)
	local recipe = Recipes.get(recipeId)
	if not ok or not recipe then
		Hooks.run("craft:blocked", { player = player, recipeId = recipeId, reason = reason })
		return false
	end
	Hooks.run("craft:start", { player = player, recipeId = recipeId, recipe = recipe })
	local done, why = consumeProduce(player, recipe)
	if done then
		Hooks.run("craft:end", { player = player, recipeId = recipeId, recipe = recipe })
	else
		Hooks.run("craft:blocked", { player = player, recipeId = recipeId, reason = why })
	end
	return done
end

-- A progress bar above the crafter that fills over `duration`. Server-built → everyone sees it.
local function showCraftBar(player: Player, duration: number, label: string): Instance?
	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not head then
		return nil
	end
	local old = head:FindFirstChild("_CraftBar")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "_CraftBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(150, 30)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgc = Instance.new("UICorner")
	bgc.CornerRadius = UDim.new(0, 4)
	bgc.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(160, 130, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 4)
	fc.Parent = fill

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "Crafting " .. label .. "…"
	text.TextColor3 = Color3.fromRGB(245, 245, 245)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 13
	text.Parent = gui

	gui.Parent = head
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
	return gui
end

-- Player-initiated craft: channel for craftTime (progress bar), re-validate, then produce.
local function channelCraft(player: Player, recipeId: string)
	if channeling[player] then
		return -- already crafting
	end
	local ok, reason = Crafting.canCraft(player, recipeId)
	local recipe = Recipes.get(recipeId)
	if not ok or not recipe then
		Hooks.run("craft:blocked", { player = player, recipeId = recipeId, reason = reason })
		return
	end

	channeling[player] = true
	Hooks.run("craft:start", { player = player, recipeId = recipeId, recipe = recipe })

	local outName = recipe.output and recipe.output.item or recipeId
	local bar = showCraftBar(player, Crafting.craftTime(recipe), tostring(outName))
	task.wait(Crafting.craftTime(recipe))
	if bar then
		bar:Destroy()
	end

	if not channeling[player] then
		return -- player left mid-craft
	end
	channeling[player] = nil

	-- Re-validate after the channel (items/inventory may have changed) before consuming.
	if not Crafting.canCraft(player, recipeId) then
		Hooks.run("craft:blocked", { player = player, recipeId = recipeId, reason = "ingredients" })
		return
	end
	local done, why = consumeProduce(player, recipe)
	if done then
		Hooks.run("craft:end", { player = player, recipeId = recipeId, recipe = recipe })
	else
		Hooks.run("craft:blocked", { player = player, recipeId = recipeId, reason = why })
	end
end

function Crafting.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Replicate recipe data so the Crafting tab can render + gate client-side.
	RecipeData.publish(Recipes.getAll())

	Remotes.event("CraftRecipe").OnServerEvent:Connect(function(player, recipeId)
		if type(recipeId) == "string" then
			channelCraft(player, recipeId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		channeling[player] = nil
	end)
end

return Crafting
