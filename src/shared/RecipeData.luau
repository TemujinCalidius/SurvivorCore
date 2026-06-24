--!nonstrict
--[[
	RecipeData — replicates recipe data from the server to clients. SHARED.

	Recipes are registered server-side (`SurvivorCore.Recipes`), so the client's registry copy is
	empty. The Crafting tab needs each recipe's ingredients + output to render and gate. Mirroring
	ItemData, the engine serialises recipes into a replicated StringValue at start(); the client
	reads them back. Recipe defs are already plain serialisable tables (id/station/ingredients/
	output), so they cross the wire as-is. Server stays authoritative for the actual craft.

		-- server (engine, at start): RecipeData.publish(SurvivorCore.Recipes.getAll())
		-- client (engine UI):        local list = RecipeData.forStation("hand")
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RecipeData = {}

local HOLDER_NAME = "SurvivorCoreRecipeData"

export type DisplayRecipe = {
	id: string,
	station: string?,
	ingredients: { { item: string, count: number } },
	output: { item: string, count: number }?,
}

local function toDisplay(def: any): DisplayRecipe?
	if not def or typeof(def.id) ~= "string" then
		return nil
	end
	local ingredients = {}
	if typeof(def.ingredients) == "table" then
		for _, ing in def.ingredients do
			if typeof(ing) == "table" and typeof(ing.item) == "string" then
				table.insert(
					ingredients,
					{ item = ing.item, count = math.max(1, math.floor(tonumber(ing.count) or 1)) }
				)
			end
		end
	end
	local output = nil
	if typeof(def.output) == "table" and typeof(def.output.item) == "string" then
		output = { item = def.output.item, count = math.max(1, math.floor(tonumber(def.output.count) or 1)) }
	end
	return {
		id = def.id,
		station = if typeof(def.station) == "string" then def.station else nil,
		ingredients = ingredients,
		output = output,
	}
end

-- ── Server: serialise + replicate ──────────────────────────────────────────
function RecipeData.publish(defs: { any })
	local out = {}
	for _, def in defs do
		local d = toDisplay(def)
		if d then
			table.insert(out, d)
		end
	end
	local holder = ReplicatedStorage:FindFirstChild(HOLDER_NAME)
	if not holder then
		holder = Instance.new("StringValue")
		holder.Name = HOLDER_NAME
		holder.Parent = ReplicatedStorage
	end
	holder.Value = HttpService:JSONEncode(out)
end

-- ── Client: read + cache ────────────────────────────────────────────────────
local cache: { DisplayRecipe }? = nil
local watching = false

local function rebuild(): { DisplayRecipe }
	local result: { DisplayRecipe } = {}
	local holder = ReplicatedStorage:WaitForChild(HOLDER_NAME, 10)
	if holder and holder:IsA("StringValue") and holder.Value ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(holder.Value)
		end)
		if ok and typeof(decoded) == "table" then
			for _, d in decoded do
				if typeof(d) == "table" and typeof(d.id) == "string" then
					table.insert(result, d)
				end
			end
		end
		if not watching then
			watching = true
			holder:GetPropertyChangedSignal("Value"):Connect(function()
				cache = nil
			end)
		end
	end
	return result
end

local function ensureCache(): { DisplayRecipe }
	local c = cache
	if not c then
		c = rebuild()
		cache = c
	end
	return c
end

function RecipeData.getAll(): { DisplayRecipe }
	return ensureCache()
end

function RecipeData.forStation(station: string): { DisplayRecipe }
	local out = {}
	for _, r in ensureCache() do
		if (r.station or "hand") == station then
			table.insert(out, r)
		end
	end
	return out
end

return RecipeData
