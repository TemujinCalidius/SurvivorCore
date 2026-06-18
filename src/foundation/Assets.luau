--[[
	Assets — typed asset-id lookup. The engine NEVER hardcodes asset ids; games
	register theirs and the engine reads them back, with a safe fallback.

		Assets.register("Sounds", "Harvest", "rbxassetid://123")
		Assets.get("Sounds", "Harvest")   -- "rbxassetid://123", or "" + warning if missing
]]

local Assets = {}

local store: { [string]: { [string]: string } } = {}

function Assets.register(category: string, key: string, assetId: string)
	store[category] = store[category] or {}
	store[category][key] = assetId
end

function Assets.registerCategory(category: string, map: { [string]: string })
	for key, id in map do
		Assets.register(category, key, id)
	end
end

function Assets.get(category: string, key: string): string
	local cat = store[category]
	local id = cat and cat[key]
	if not id or id == "" then
		warn(`[SurvivorCore.Assets] missing asset '{category}.{key}' — using fallback`)
		return ""
	end
	return id
end

return Assets
