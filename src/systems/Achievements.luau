--!nonstrict
--[[
	Achievements — server. The achievement runtime: always-on counters → threshold → unlock-once.

	The architecture is ported from The Counter Earth's proven AchievementService, made
	content-free: instead of hand-written event mappings, the shared `Progression` stream bumps
	GENERIC counters for every (kind, target) — `gathers_total`, `gathers_<item>`, `crafts_total`,
	`crafts_<item>`, `kills_<mobType>`, `uses_<item>`, `quests_completed`, … — so an achievement
	def is FLAT and no-code-authorable:

		SurvivorCore.Achievements.register({
			key = "husk_slayer", name = "Husk Slayer",
			counter = "kills_husk", threshold = 3,
		})

	Games add custom mappings via `SurvivorCore.Progression.map`, bump bespoke counters with
	`Achievements.addCount`, or unlock directly with `Achievements.award`. State replicates as ONE
	JSON Player attribute (`AchievementData.STATE_ATTR`); unlocks fire `achievement:unlocked`
	(Hooks + EventBridge) and a toast. Tuning: the "Achievements" Config section. Session-scoped
	(persistence is a future system). Started by SurvivorCore.start().
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "SurvivorCore.Achievements is server-only — booted by SurvivorCore.start()")

local Registries = require(script.Parent.Parent.registries)
local Progression = require(script.Parent.Progression)
local Hooks = require(script.Parent.Parent.foundation.Hooks)
local EventBridge = require(script.Parent.Parent.foundation.EventBridge)
local Remotes = require(script.Parent.Parent.shared.Remotes)
local AchievementData = require(script.Parent.Parent.shared.AchievementData)
local AchievementsConfig = require(script.Parent.Parent.shared.AchievementsConfig)

local Achievements = {}

local started = false

-- Validated display defs (key → def) and, per counter, the defs it can unlock.
local defs: { [string]: AchievementData.Achievement } = {}
local byCounter: { [string]: { AchievementData.Achievement } } = {}

type PlayerState = { c: { [string]: number }, u: { [string]: boolean } }
local states: { [Player]: PlayerState } = {}

local function getState(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { c = {}, u = {} }
		states[player] = s
	end
	return s
end

local function writeState(player: Player)
	local s = getState(player)
	player:SetAttribute(AchievementData.STATE_ATTR, HttpService:JSONEncode({ v = 1, c = s.c, u = s.u }))
end

local function unlock(player: Player, def: AchievementData.Achievement)
	local s = getState(player)
	if s.u[def.key] then
		return
	end
	s.u[def.key] = true
	local ctx = { player = player, key = def.key, def = def }
	Hooks.run("achievement:unlocked", ctx)
	EventBridge.fire("achievement:unlocked", player, { key = def.key, def = def })
	if AchievementsConfig.get().Toasts ~= false then
		Remotes.event("Notify"):FireClient(player, {
			kind = "achievement",
			title = "Achievement unlocked",
			body = def.name,
			icon = def.icon,
		})
	end
end

-- Bump a counter and unlock anything it satisfies. The single write path for all progress.
local function bump(player: Player, counterId: string, amount: number)
	local s = getState(player)
	s.c[counterId] = (s.c[counterId] or 0) + amount
	local watchers = byCounter[counterId]
	if watchers then
		for _, def in watchers do
			if not s.u[def.key] and s.c[counterId] >= def.threshold then
				unlock(player, def)
			end
		end
	end
	writeState(player)
end

-- ── Public API (attached to SurvivorCore.Achievements after start) ──────────

-- Manually unlock an achievement (story beats, secrets — things counters can't express).
function Achievements.award(player: Player, key: string): boolean
	local def = defs[key]
	if not def then
		warn(`[SurvivorCore.Achievements] award: unknown key '{tostring(key)}'`)
		return false
	end
	if getState(player).u[key] then
		return false
	end
	unlock(player, def)
	writeState(player)
	return true
end

-- Bump a bespoke counter from game code (pairs with defs authored against that counter id).
function Achievements.addCount(player: Player, counterId: string, amount: number?)
	bump(player, tostring(counterId), math.max(1, math.floor(tonumber(amount) or 1)))
end

function Achievements.isUnlocked(player: Player, key: string): boolean
	return getState(player).u[key] == true
end

function Achievements.getState(player: Player)
	return AchievementData.decodeState(player)
end

-- ── Boot ─────────────────────────────────────────────────────────────────────

local function addPlayer(player: Player)
	getState(player)
	writeState(player)
end

function Achievements.start(_options: { [string]: any }?)
	if started then
		return
	end
	started = true

	-- Snapshot + validate the registered defs, index by counter, replicate for the tab.
	for _, raw in Registries.Achievements.getAll() do
		local def = AchievementData.toDisplay(raw)
		if def then
			defs[def.key] = def
			local list = byCounter[def.counter]
			if not list then
				list = {}
				byCounter[def.counter] = list
			end
			table.insert(list, def)
		end
	end
	AchievementData.publish(Registries.Achievements.getAll())

	Remotes.event("Notify") -- eager (shared with Quests; idempotent)

	-- Generic counters from the shared progress stream: kind totals + per-target.
	Progression.onProgress(function(player, kind, target, amount)
		for _, counterId in Progression.counterIds(kind, target) do
			bump(player, counterId, amount)
		end
	end)

	for _, player in Players:GetPlayers() do
		task.defer(addPlayer, player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return Achievements
