--[[
	StatConfig — resolves the effective survival-stat models by merging three layers
	(last wins):
	  1. engine defaults  — the Stats registry (populated by StatDefs).
	  2. developer path    — Config.override("SurvivalStats", { Hunger = { ratePerSecond = … } }).
	  3. owner / no-code   — a `SurvivalStatsConfig` Configuration instance in
	                         ReplicatedStorage, whose per-stat children carry Attributes
	                         the owner edits in Studio (highest priority).

	SHARED: the server reads this for the tick loop; the client reads it for per-bar
	defaults (Max / Invert / WarnAt) and the fallback HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Parent.foundation.Config)
local Registries = require(script.Parent.Parent.registries)

local StatConfig = {}

StatConfig.CONFIG_SECTION = "SurvivalStats"
StatConfig.CONFIG_INSTANCE_NAME = "SurvivalStatsConfig"

-- Attribute name on the Studio Configuration child -> resolved field name. Only OWNER-tunable
-- knobs live here. Stat *semantics* — `invert` (fill direction) and `dangerHigh` (which end is
-- bad) — are engine-owned and deliberately NOT overridable from the instance, so a stale or
-- place-saved instance can never freeze them to a wrong value across an engine update (the bug
-- where Poison/Hunger filled the wrong way). For a one-off display flip, set the per-bar
-- `Invert` attribute on the HUD bar itself instead.
local STUDIO_ATTR_MAP = {
	RatePerSecond = "ratePerSecond",
	Max = "max",
	Start = "start",
	WarnAt = "warnAt",
	Display = "display",
	Icon = "icon",
	ValueFormat = "valueFormat",
}

local function applyTable(target: { [string]: any }, override: { [string]: any }?)
	if typeof(override) ~= "table" then
		return
	end
	for key, value in override do
		target[key] = value
	end
end

local function applyStudio(target: { [string]: any }, configInstance: Instance?, statName: string)
	if not configInstance then
		return
	end
	local node = configInstance:FindFirstChild(statName)
	if not node then
		return
	end
	for attr, field in STUDIO_ATTR_MAP do
		local value = node:GetAttribute(attr)
		if value ~= nil then
			target[field] = value
		end
	end
end

export type ResolvedStat = {
	name: string,
	attribute: string,
	start: number,
	max: number,
	ratePerSecond: number,
	dangerHigh: boolean,
	invert: boolean,
	warnAt: number,
	display: boolean,
	icon: string, -- HUD icon asset id, "" when none (engine ships "" — content-free)
	valueFormat: string, -- HUD numeric readout: "fraction" | "percent" | "value" | "none"
}

-- Returns the merged stat models, both as an ordered array and a name lookup.
function StatConfig.resolve(): { stats: { ResolvedStat }, byName: { [string]: ResolvedStat } }
	local section = Config.get(StatConfig.CONFIG_SECTION) -- nil if StatDefs never installed
	local configInstance = ReplicatedStorage:FindFirstChild(StatConfig.CONFIG_INSTANCE_NAME)

	local stats = {}
	local byName = {}
	for _, def in Registries.Stats.getAll() do
		local resolved = {
			name = def.name,
			attribute = def.attribute or def.name,
			start = def.start,
			max = def.max,
			ratePerSecond = def.ratePerSecond,
			dangerHigh = def.dangerHigh or false,
			invert = def.invert,
			warnAt = def.warnAt,
			display = def.display,
			icon = def.icon or "",
			valueFormat = def.valueFormat or "fraction",
		}
		if section then
			applyTable(resolved, section[def.name])
		end
		applyStudio(resolved, configInstance, def.name)
		table.insert(stats, resolved)
		byName[def.name] = resolved
	end
	return { stats = stats, byName = byName }
end

-- The live Studio config instance, if present (used to watch for owner edits).
function StatConfig.getConfigInstance(): Instance?
	return ReplicatedStorage:FindFirstChild(StatConfig.CONFIG_INSTANCE_NAME)
end

return StatConfig
