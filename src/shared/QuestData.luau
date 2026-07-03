--!nonstrict
--[[
	QuestData — quest def replication + the QuestLog schema. SHARED.

	Two jobs, both sides of the wire:
	1. DEFS: quests are registered server-side; the client's registry copy is empty. Mirroring
	   RecipeData, the engine serialises the (normalized) defs into a replicated StringValue at
	   start(); the Quests tab reads them back. `QuestData.normalize` is the ONE place both the
	   canonical nested shape and the flat no-code shape (admin plugin / loadFromFolder attributes)
	   become the same def — the runtime and the UI never see a flat def.
	2. LOG: per-player progress replicates as ONE JSON Player attribute (`QuestLog`), written by the
	   server runtime after every mutation; the client decodes it with `QuestData.decodeLog`.

		-- server (engine, at start): QuestData.publish(SurvivorCore.Quests.getAll())
		-- client (Quests tab):       QuestData.getAll(), QuestData.decodeLog(localPlayer)
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestData = {}

local HOLDER_NAME = "SurvivorCoreQuestData"

-- The per-player progress attribute (JSON):
-- { v = 1, active = { [id] = { p = {n, …} } }, ready = { [id] = true }, done = { [id] = true } }
-- `p` is a progress array parallel to the quest's objectives. `ready` = objectives met but the
-- reward not yet granted (turn-in pending, or the inventory was full).
QuestData.LOG_ATTR = "QuestLog"

export type Objective = { type: string, target: string, count: number }
export type Reward = { item: string, count: number }
export type Quest = {
	id: string,
	name: string,
	description: string?,
	objectives: { Objective },
	rewards: { Reward },
	autoStart: boolean,
	requires: string?,
	turnIn: boolean,
}

local OBJECTIVE_TYPES = { gather = true, craft = true, kill = true, use = true }

-- Normalize a registered def (nested OR flat no-code fields) into the canonical Quest shape.
-- Returns nil (with a warn) for defs missing the essentials, so a bad authored quest can't
-- break publish or the runtime.
function QuestData.normalize(def: any): Quest?
	if typeof(def) ~= "table" or typeof(def.id) ~= "string" or def.id == "" then
		return nil
	end

	-- Objectives: canonical nested list, else the flat single-objective fields.
	local objectives: { Objective } = {}
	if typeof(def.objectives) == "table" then
		for _, o in def.objectives do
			if typeof(o) == "table" and OBJECTIVE_TYPES[o.type] and typeof(o.target) == "string" then
				table.insert(objectives, {
					type = o.type,
					target = o.target,
					count = math.max(1, math.floor(tonumber(o.count) or 1)),
				})
			end
		end
	elseif typeof(def.objectiveType) == "string" and OBJECTIVE_TYPES[def.objectiveType] then
		table.insert(objectives, {
			type = def.objectiveType,
			target = tostring(def.objectiveTarget or ""),
			count = math.max(1, math.floor(tonumber(def.objectiveCount) or 1)),
		})
	end
	if #objectives == 0 then
		warn(`[SurvivorCore.Quests] quest '{def.id}' has no valid objectives — skipped`)
		return nil
	end

	-- Rewards: nested list, else the flat pair; rewards are optional.
	local rewards: { Reward } = {}
	if typeof(def.rewards) == "table" then
		for _, r in def.rewards do
			if typeof(r) == "table" and typeof(r.item) == "string" and r.item ~= "" then
				table.insert(rewards, { item = r.item, count = math.max(1, math.floor(tonumber(r.count) or 1)) })
			end
		end
	elseif typeof(def.rewardItem) == "string" and def.rewardItem ~= "" then
		table.insert(rewards, {
			item = def.rewardItem,
			count = math.max(1, math.floor(tonumber(def.rewardCount) or 1)),
		})
	end

	local requires = if typeof(def.requires) == "string" and def.requires ~= "" then def.requires else nil

	return {
		id = def.id,
		name = if typeof(def.name) == "string" and def.name ~= "" then def.name else def.id,
		description = if typeof(def.description) == "string" and def.description ~= "" then def.description else nil,
		objectives = objectives,
		rewards = rewards,
		autoStart = def.autoStart == true,
		requires = requires,
		turnIn = def.turnIn == true,
	}
end

-- ── Server: serialise + replicate ──────────────────────────────────────────
function QuestData.publish(defs: { any })
	local out = {}
	for _, def in defs do
		local q = QuestData.normalize(def)
		if q then
			table.insert(out, q)
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

-- ── Both sides: decode a player's QuestLog attribute (always returns a full shape) ──
function QuestData.decodeLog(player: Player): any
	local raw = player:GetAttribute(QuestData.LOG_ATTR)
	if typeof(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and typeof(decoded) == "table" then
			decoded.active = if typeof(decoded.active) == "table" then decoded.active else {}
			decoded.ready = if typeof(decoded.ready) == "table" then decoded.ready else {}
			decoded.done = if typeof(decoded.done) == "table" then decoded.done else {}
			return decoded
		end
	end
	return { v = 1, active = {}, ready = {}, done = {} }
end

-- ── Client: read + cache ────────────────────────────────────────────────────
local cache: { Quest }? = nil
local watching = false

local function rebuild(): { Quest }
	local result: { Quest } = {}
	local holder = ReplicatedStorage:WaitForChild(HOLDER_NAME, 10)
	if holder and holder:IsA("StringValue") and holder.Value ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(holder.Value)
		end)
		if ok and typeof(decoded) == "table" then
			for _, q in decoded do
				if typeof(q) == "table" and typeof(q.id) == "string" then
					table.insert(result, q)
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

local function ensureCache(): { Quest }
	local c = cache
	if not c then
		c = rebuild()
		cache = c
	end
	return c
end

function QuestData.getAll(): { Quest }
	return ensureCache()
end

function QuestData.get(id: string): Quest?
	for _, q in ensureCache() do
		if q.id == id then
			return q
		end
	end
	return nil
end

return QuestData
