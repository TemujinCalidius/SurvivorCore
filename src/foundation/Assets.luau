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

-- Like `get` but SILENT: returns "" for a missing/empty asset without warning.
-- Use it on hot paths (e.g. the HUD resolving an optional per-stat icon every render)
-- where a missing id is an expected, non-error case.
function Assets.tryGet(category: string, key: string): string
	local cat = store[category]
	local id = cat and cat[key]
	if typeof(id) == "string" then
		return id
	end
	return ""
end

return Assets
