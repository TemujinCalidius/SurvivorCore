--!nonstrict
--[[
	AchievementData — achievement def replication + the AchievementState schema. SHARED.

	Achievement defs are FLAT — { key, name, description?, icon?, counter, threshold } — so the
	no-code (attribute) and code shapes are identical and no normalization pass is needed; this
	module just validates + replicates them (RecipeData pattern) and owns the per-player state
	attribute schema the server runtime writes and the Achievements tab reads.

		-- server (engine, at start): AchievementData.publish(SurvivorCore.Achievements.getAll())
		-- client (Achievements tab): AchievementData.getAll(), AchievementData.decodeState(localPlayer)
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementData = {}

local HOLDER_NAME = "SurvivorCoreAchievementData"

-- The per-player state attribute (JSON):
-- { v = 1, c = { [counterId] = n }, u = { [key] = true } }  (c = counters, u = unlocked)
AchievementData.STATE_ATTR = "AchievementState"

export type Achievement = {
	key: string,
	name: string,
	description: string?,
	icon: string?,
	counter: string,
	threshold: number,
}

local function toDisplay(def: any): Achievement?
	if typeof(def) ~= "table" or typeof(def.key) ~= "string" or def.key == "" then
		return nil
	end
	if typeof(def.counter) ~= "string" or def.counter == "" then
		warn(`[SurvivorCore.Achievements] '{def.key}' has no counter — skipped`)
		return nil
	end
	return {
		key = def.key,
		name = if typeof(def.name) == "string" and def.name ~= "" then def.name else def.key,
		description = if typeof(def.description) == "string" and def.description ~= "" then def.description else nil,
		icon = if typeof(def.icon) == "string" and def.icon ~= "" then def.icon else nil,
		counter = def.counter,
		threshold = math.max(1, math.floor(tonumber(def.threshold) or 1)),
	}
end
AchievementData.toDisplay = toDisplay

-- ── Server: serialise + replicate ──────────────────────────────────────────
function AchievementData.publish(defs: { any })
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

-- ── Both sides: decode a player's AchievementState attribute ────────────────
function AchievementData.decodeState(player: Player): any
	local raw = player:GetAttribute(AchievementData.STATE_ATTR)
	if typeof(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and typeof(decoded) == "table" then
			decoded.c = if typeof(decoded.c) == "table" then decoded.c else {}
			decoded.u = if typeof(decoded.u) == "table" then decoded.u else {}
			return decoded
		end
	end
	return { v = 1, c = {}, u = {} }
end

-- ── Client: read + cache ────────────────────────────────────────────────────
local cache: { Achievement }? = nil
local watching = false

local function rebuild(): { Achievement }
	local result: { Achievement } = {}
	local holder = ReplicatedStorage:WaitForChild(HOLDER_NAME, 10)
	if holder and holder:IsA("StringValue") and holder.Value ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(holder.Value)
		end)
		if ok and typeof(decoded) == "table" then
			for _, d in decoded do
				if typeof(d) == "table" and typeof(d.key) == "string" then
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

function AchievementData.getAll(): { Achievement }
	local c = cache
	if not c then
		c = rebuild()
		cache = c
	end
	return c
end

return AchievementData
