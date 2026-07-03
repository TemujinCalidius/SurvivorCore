--!nonstrict
--[[
	Quests — server. The quest runtime (issue #10): accept → progress → complete → reward.

	Defs come from the `Quests` registry (code-authored nested, or flat no-code via the admin
	plugin / SurvivorCoreContent — `QuestData.normalize` makes them identical). Progress is driven
	by the shared `Progression` stream (gather/craft/kill/use), so quests need zero wiring into the
	systems that generate events. An objective with a blank target matches ANY target of its kind
	("kill 3 of anything").

	Lifecycle per quest per player: `active` (progress array parallels the objectives) →
	objectives met → `ready` (only if the quest needs a turn-in, or the reward didn't fit) →
	`done`. Rewards are NEVER lost: a grant that doesn't fit (full inventory) parks the remainder
	and retries on every `inventory:changed` until it lands. Auto-start quests begin on join, and
	chain — completing a prerequisite auto-starts dependents marked autoStart.

	State replicates as ONE JSON Player attribute (`QuestData.LOG_ATTR`); the Quests tab re-renders
	from it. Fires quest:started/progress/completed/blocked through Hooks AND EventBridge.
	Tuning: the "Quests" Config section. Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Quests is server-only — booted by SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local Inventory = require(script.Parent.Inventory)
local Progression = require(script.Parent.Progression)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local QuestData = require(script.Parent.Parent.shared.QuestData)
local QuestsConfig = require(script.Parent.Parent.shared.QuestsConfig)

local Quests = {}

local started = false

-- Normalized defs, id → Quest (built once at start from the registry).
local defs: { [string]: QuestData.Quest } = {}

-- Per-player runtime state. `active[id].p` parallels the def's objectives; `ready[id] = true`
-- awaits turn-in / reward room; `pendingRewards[id]` = rewards still owed and `needsGiver[id]`
-- marks a ready quest that must be turned in at a QuestGiver (both server-side only).
type PlayerState = {
	active: { [string]: { p: { number } } },
	ready: { [string]: boolean },
	done: { [string]: boolean },
	pendingRewards: { [string]: { QuestData.Reward } },
	needsGiver: { [string]: boolean },
}
local states: { [Player]: PlayerState } = {}

local function getState(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { active = {}, ready = {}, done = {}, pendingRewards = {}, needsGiver = {} }
		states[player] = s
	end
	return s
end

-- Serialize the client-facing slice of the state into the QuestLog attribute.
local function writeLog(player: Player)
	local s = getState(player)
	local log = { v = 1, active = s.active, ready = s.ready, done = s.done }
	player:SetAttribute(QuestData.LOG_ATTR, HttpService:JSONEncode(log))
end

local function emit(event: string, player: Player, ctx: { [string]: any })
	ctx.player = player
	Hooks.run(event, ctx)
	EventBridge.fire(event, player, ctx)
end

local function toast(player: Player, payload: { [string]: any })
	if QuestsConfig.get().Toasts == false then
		return
	end
	Remotes.event("Notify"):FireClient(player, payload)
end

local function activeCount(s: PlayerState): number
	local n = 0
	for _ in s.active do
		n += 1
	end
	return n
end

local function objectivesMet(quest: QuestData.Quest, progress: { number }): boolean
	for i, obj in quest.objectives do
		if (progress[i] or 0) < obj.count then
			return false
		end
	end
	return true
end

-- Grant a quest's (remaining) rewards. Returns the rewards that still don't fit (empty = all in).
local function grantRewards(player: Player, rewards: { QuestData.Reward }): { QuestData.Reward }
	local remaining = {}
	for _, reward in rewards do
		if not Inventory.add(player, reward.item, reward.count) then
			table.insert(remaining, reward)
		end
	end
	return remaining
end

-- Re-entrancy guard: granting a reward fires inventory:changed, whose retry handler must not
-- re-enter tryFinish for the same quest mid-grant (that would double-grant).
local finishing: { [Player]: { [string]: boolean } } = {}

-- Finish a quest whose objectives are met: grant rewards (parking any that don't fit), and if
-- everything landed, move it to done + fire completed + chain any autoStart dependents.
local function tryFinish(player: Player, questId: string)
	local s = getState(player)
	local quest = defs[questId]
	if not quest then
		return
	end
	local f = finishing[player]
	if f and f[questId] then
		return
	end
	f = f or {}
	finishing[player] = f
	f[questId] = true

	local owed = s.pendingRewards[questId] or quest.rewards
	local remaining = grantRewards(player, owed)
	if #remaining > 0 then
		-- No room for (some of) the reward: park it in `ready` and retry when the inventory changes.
		s.active[questId] = nil
		s.ready[questId] = true
		s.pendingRewards[questId] = remaining
		s.needsGiver[questId] = nil -- past the giver gate (if any); now only waiting for room
		writeLog(player)
		f[questId] = nil
		return
	end

	s.active[questId] = nil
	s.ready[questId] = nil
	s.pendingRewards[questId] = nil
	s.needsGiver[questId] = nil
	s.done[questId] = true
	writeLog(player)
	f[questId] = nil

	emit("quest:completed", player, { questId = questId, def = quest })
	toast(player, { kind = "quest", title = "Quest complete", body = quest.name })

	-- Chain: auto-start any autoStart quest this completion unlocks.
	for id, def in defs do
		if def.autoStart and def.requires == questId then
			Quests.accept(player, id)
		end
	end
end

-- ── Public API (attached to SurvivorCore.Quests after start) ─────────────────

function Quests.accept(player: Player, questId: string): (boolean, string?)
	local s = getState(player)
	local quest = defs[questId]
	local reason: string? = nil
	if not quest then
		reason = "unknown"
	elseif s.done[questId] then
		reason = "done"
	elseif s.active[questId] or s.ready[questId] then
		reason = "active"
	elseif quest.requires and not s.done[quest.requires] then
		reason = "requires"
	else
		local maxActive = tonumber(QuestsConfig.get().MaxActive) or 0
		if maxActive > 0 and activeCount(s) >= maxActive then
			reason = "max"
		end
	end
	if reason then
		emit("quest:blocked", player, { questId = questId, reason = reason })
		return false, reason
	end

	local progress = table.create(#quest.objectives, 0)
	s.active[questId] = { p = progress }
	writeLog(player)
	emit("quest:started", player, { questId = questId, def = quest })
	return true
end

-- Turn in a `ready` quest (the QuestGiver path) — also completes a met-but-unclaimed quest.
function Quests.complete(player: Player, questId: string): (boolean, string?)
	local s = getState(player)
	local quest = defs[questId]
	if not quest then
		return false, "unknown"
	end
	if s.done[questId] then
		return false, "done"
	end
	if s.ready[questId] then
		s.needsGiver[questId] = nil -- the giver gate is satisfied by this turn-in
		tryFinish(player, questId)
		return s.done[questId] == true, if s.done[questId] then nil else "full"
	end
	local entry = s.active[questId]
	if entry and objectivesMet(quest, entry.p) then
		tryFinish(player, questId)
		return s.done[questId] == true, if s.done[questId] then nil else "full"
	end
	return false, "incomplete"
end

function Quests.abandon(player: Player, questId: string): boolean
	local s = getState(player)
	if not s.active[questId] then
		return false
	end
	s.active[questId] = nil
	writeLog(player)
	return true
end

function Quests.isActive(player: Player, questId: string): boolean
	local s = getState(player)
	return s.active[questId] ~= nil or s.ready[questId] == true
end

function Quests.isCompleted(player: Player, questId: string): boolean
	return getState(player).done[questId] == true
end

function Quests.getLog(player: Player)
	return QuestData.decodeLog(player)
end

-- ── Progress driver ──────────────────────────────────────────────────────────

local function onProgress(player: Player, kind: string, target: string?, amount: number)
	local s = states[player]
	if not s then
		return
	end
	for questId, entry in s.active do
		local quest = defs[questId]
		if quest then
			local changed = false
			for i, obj in quest.objectives do
				local matches = obj.type == kind and (obj.target == "" or obj.target == (target or ""))
				if matches and (entry.p[i] or 0) < obj.count then
					entry.p[i] = math.min(obj.count, (entry.p[i] or 0) + amount)
					changed = true
					emit("quest:progress", player, {
						questId = questId,
						def = quest,
						index = i,
						count = entry.p[i],
					})
				end
			end
			if changed then
				writeLog(player)
				if objectivesMet(quest, entry.p) then
					if quest.turnIn then
						s.active[questId] = nil
						s.ready[questId] = true
						s.pendingRewards[questId] = quest.rewards
						s.needsGiver[questId] = true
						writeLog(player)
						toast(player, {
							kind = "quest",
							title = "Objectives complete",
							body = quest.name .. " — turn it in!",
						})
					else
						tryFinish(player, questId)
					end
				end
			end
		end
	end
end

-- ── Boot ─────────────────────────────────────────────────────────────────────

local function addPlayer(player: Player)
	local s = getState(player)
	writeLog(player)
	for id, def in defs do
		if def.autoStart and not def.requires and not s.done[id] and not s.active[id] then
			Quests.accept(player, id)
		end
	end
end

function Quests.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Snapshot + normalize the registered defs, then replicate them for the Quests tab.
	for _, raw in Registries.Quests.getAll() do
		local q = QuestData.normalize(raw)
		if q then
			defs[q.id] = q
		end
	end
	QuestData.publish(Registries.Quests.getAll())

	-- Eager so clients can connect at startup.
	Remotes.event("Notify")

	Progression.onProgress(onProgress)

	-- Client requests: accept via a giver prompt UI / turn-in. Server re-validates everything.
	Remotes.event("QuestAccept").OnServerEvent:Connect(function(player, questId)
		if typeof(questId) == "string" then
			Quests.accept(player, questId)
		end
	end)
	Remotes.event("QuestTurnIn").OnServerEvent:Connect(function(player, questId)
		if typeof(questId) == "string" then
			Quests.complete(player, questId)
		end
	end)

	-- A parked reward retries whenever the player's inventory changes (something freed up).
	-- Quests still awaiting a giver turn-in (needsGiver) are NOT auto-delivered.
	Hooks.on("inventory:changed", function(ctx)
		local player = ctx and ctx.player
		local s = player and states[player]
		if not s then
			return
		end
		for questId in pairs(s.ready) do
			if not s.needsGiver[questId] then
				tryFinish(player, questId)
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		task.defer(addPlayer, player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		finishing[player] = nil
	end)
end

return Quests
