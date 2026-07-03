--!nonstrict
--[[
	Progression — server. The ONE translation layer between raw gameplay events and the systems
	that track player progress (Quests, Achievements — and anything a game adds).

	It subscribes to the EventBridge once and turns events into a semantic stream of
	(player, kind, target?, amount) tuples, so target extraction (the item from a gather ctx, the
	output item from a craft ctx, the mobType from a mob death) lives in exactly one place.

	Built-in mappings (content-free):
	  gather:hit       → ("gather", item, granted)
	  craft:end        → ("craft",  output item or recipeId, output count)
	  mob:died         → ("kill",   mobType, 1)      -- canonical kill source: fires ONCE per mob
	                                                  -- death (combat:kill also fires for the same
	                                                  -- death — counting both would double-count)
	  item:use         → ("use",    itemId, 1)
	  quest:completed  → ("quest",  questId, 1)

	Games add their own with `Progression.map(eventType, resolver)`. Counter naming (what
	achievement defs author against): `Progression.counterIds(kind, target)` →
	{ "<kind>s_total", "<kind>s_<target>" } — e.g. gathers_total / gathers_reed, kills_husk.
]]

local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Progression is server-only — booted by SurvivorCore.start()")

local EventBridge = require(script.Parent.Parent.foundation.EventBridge)

local Progression = {}

local started = false

type Resolver = (player: Player, data: { [string]: any }) -> (string?, string?, number?)
type ProgressCb = (player: Player, kind: string, target: string?, amount: number) -> ()

local resolvers: { [string]: Resolver } = {}
local listeners: { ProgressCb } = {}

-- ── Built-in event → (kind, target, amount) mappings ────────────────────────

resolvers["gather:hit"] = function(_player, data)
	local item = tostring(data.item or "")
	if item == "" then
		return nil
	end
	return "gather", item, math.max(1, math.floor(tonumber(data.granted) or 1))
end

resolvers["craft:end"] = function(_player, data)
	local recipe = data.recipe
	local output = recipe and recipe.output
	local target = (typeof(output) == "table" and typeof(output.item) == "string" and output.item)
		or tostring(data.recipeId or "")
	if target == "" then
		return nil
	end
	local count = (typeof(output) == "table" and math.max(1, math.floor(tonumber(output.count) or 1))) or 1
	return "craft", target, count
end

resolvers["mob:died"] = function(_player, data)
	-- player (the bridge's 2nd arg) is the killer; nil = environmental death (no progress).
	local mobType = tostring(data.mobType or "")
	if mobType == "" then
		return nil
	end
	return "kill", mobType, 1
end

resolvers["item:use"] = function(_player, data)
	local itemId = tostring(data.itemId or "")
	if itemId == "" then
		return nil
	end
	return "use", itemId, 1
end

resolvers["quest:completed"] = function(_player, data)
	local questId = tostring(data.questId or "")
	if questId == "" then
		return nil
	end
	return "quest", questId, 1
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Subscribe to the semantic progress stream. Returns an unsubscribe function.
function Progression.onProgress(cb: ProgressCb): () -> ()
	table.insert(listeners, cb)
	return function()
		local i = table.find(listeners, cb)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- Register (or override) a custom event mapping — how a game teaches quests/achievements about
-- its own EventBridge events. resolver(player, data) -> (kind, target?, amount?) or nil to skip.
function Progression.map(eventType: string, resolver: Resolver)
	assert(typeof(eventType) == "string" and eventType ~= "", "Progression.map: eventType required")
	assert(typeof(resolver) == "function", "Progression.map: resolver must be a function")
	resolvers[eventType] = resolver
end

-- The counter ids a (kind, target) bump feeds — the naming rule achievement defs author against.
function Progression.counterIds(kind: string, target: string?): { string }
	local ids = { kind .. "s_total" }
	if target and target ~= "" then
		table.insert(ids, kind .. "s_" .. target)
	end
	return ids
end

function Progression.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	EventBridge.onFire(function(eventType, player, data)
		if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		local resolver = resolvers[eventType]
		if not resolver then
			return
		end
		local kind, target, amount = resolver(player, data or {})
		if not kind then
			return
		end
		local n = math.max(1, math.floor(tonumber(amount) or 1))
		for _, cb in listeners do
			task.spawn(cb, player, kind, target, n)
		end
	end)
end

return Progression
