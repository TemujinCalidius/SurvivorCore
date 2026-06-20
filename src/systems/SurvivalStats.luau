--[[
	SurvivalStats — the server-side survival simulation. SERVER-ONLY.

	Stores each stat as a Player Attribute (which auto-replicates to that player's
	client, so the HUD needs no RemoteEvents), and ticks every stat by its signed
	`ratePerSecond` toward 0 / max. Owners retune live via the Studio
	`SurvivalStatsConfig` instance; this service re-resolves when it changes.

	`installHud()` deploys the bundled HUD/config templates for drop-in consumers
	that haven't supplied their own.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

assert(RunService:IsServer(), "SurvivorCore.SurvivalStats is server-only — require it via SurvivorCore.start()")

local StatConfig = require(script.Parent.Parent.stats.StatConfig)

local HUD_NAME = "SurvivalHud"
local LOADER_NAME = "HudLoader"
local BAR_TAG = "SurvivorStatBar"
local TICK_INTERVAL = 0.1 -- 10 Hz: smooth bars without flooding attribute replication

local SurvivalStats = {}

local started = false
local resolved: any = nil -- cached StatConfig.resolve() result

-- Per-player, per-stat runtime modifiers: a named rate delta (optionally timed) layered on
-- top of a stat's base ratePerSecond. This is how DYNAMIC effects work — poison ticking up
-- until cured, bleeding until clotted, sprint draining energy until you stop, furniture
-- regen while seated. The effective tick rate = base + sum(active modifiers) per player.
export type ModifierSpec = {
	ratePerSecond: number, -- signed delta added to the stat's effective rate while active
	source: string, -- stable key used to remove it later (e.g. "venom", "sprint", "cut#3")
	duration: number?, -- optional seconds; nil = lasts until explicitly removed
}

type Modifier = { ratePerSecond: number, remaining: number? }

-- modifiers[player][statName][source] = Modifier
local modifiers: { [Player]: { [string]: { [string]: Modifier } } } = {}

local function refresh()
	resolved = StatConfig.resolve()
end

local function initPlayer(player: Player)
	if not resolved then
		return
	end
	for _, stat in resolved.stats do
		if player:GetAttribute(stat.attribute) == nil then
			player:SetAttribute(stat.attribute, stat.start)
		end
	end
end

-- Re-resolve the moment the owner edits the Studio config instance, so no-code
-- rate tweaks take effect without a restart.
local function watchConfig()
	local function bindInstance(instance: Instance)
		instance.AttributeChanged:Connect(refresh)
		for _, child in instance:GetChildren() do
			child.AttributeChanged:Connect(refresh)
		end
		instance.ChildAdded:Connect(function(child)
			child.AttributeChanged:Connect(refresh)
			refresh()
		end)
	end

	local existing = StatConfig.getConfigInstance()
	if existing then
		bindInstance(existing)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == StatConfig.CONFIG_INSTANCE_NAME then
			refresh()
			bindInstance(child)
		end
	end)
end

local function hudPresentInStarterGui(): boolean
	if StarterGui:FindFirstChild(HUD_NAME) then
		return true
	end
	for _, instance in CollectionService:GetTagged(BAR_TAG) do
		if instance:IsDescendantOf(StarterGui) then
			return true
		end
	end
	return false
end

-- Deploy the bundled templates if the consumer hasn't supplied their own. No-op for
-- source/demo consumers (who mount the templates directly) and when an owner HUD
-- already exists. Cloned into StarterGui so it reaches players via the native
-- StarterGui -> PlayerGui copy on spawn.
function SurvivalStats.installHud()
	local root = script.Parent.Parent -- the SurvivorCore root model
	local templates = root:FindFirstChild("Templates")
	if not templates then
		return
	end

	local configTemplate = templates:FindFirstChild(StatConfig.CONFIG_INSTANCE_NAME)
	if configTemplate and not ReplicatedStorage:FindFirstChild(StatConfig.CONFIG_INSTANCE_NAME) then
		configTemplate:Clone().Parent = ReplicatedStorage
	end

	local hudTemplate = templates:FindFirstChild(HUD_NAME)
	if hudTemplate and not hudPresentInStarterGui() then
		hudTemplate:Clone().Parent = StarterGui
	end

	-- The client boot loader rides StarterPlayerScripts (copied to each joiner).
	local loaderTemplate = templates:FindFirstChild(LOADER_NAME)
	if loaderTemplate then
		local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		if starterScripts and not starterScripts:FindFirstChild(LOADER_NAME) then
			loaderTemplate:Clone().Parent = starterScripts
		end
	end
end

-- ---------------------------------------------------------------------------
-- Runtime stat operations (SERVER). The dynamic layer over the base rates:
-- instant deltas + named, optionally-timed rate modifiers. Surfaced on
-- SurvivorCore.Stats once start() has run (they act on live players).
-- ---------------------------------------------------------------------------

-- The merged (defaults → overrides) model for a stat, or nil if unknown / pre-start.
local function statByName(name: string): any
	return resolved and resolved.byName[name] or nil
end

-- Current value of a stat for a player (reads the backing Player Attribute), or nil.
function SurvivalStats.getValue(player: Player, name: string): number?
	local stat = statByName(name)
	if not stat then
		return nil
	end
	local value = player:GetAttribute(stat.attribute)
	return if typeof(value) == "number" then value else nil
end

-- The merged stat definition (max / start / dangerHigh / …) for a stat, or nil if unknown.
-- Lets other systems read a stat's range without re-resolving the config.
function SurvivalStats.getDefinition(name: string): any
	return statByName(name)
end

-- Apply a one-time signed delta to a stat (clamped to 0..max), returning the new value.
-- Use for hits, costs and consumption — a poison dart `adjust(plr, "Poison", 1)`, a jump's
-- energy cost `adjust(plr, "Energy", -4)`, eating `adjust(plr, "Hunger", -30)`.
function SurvivalStats.adjust(player: Player, name: string, delta: number): number?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Stats.adjust: player must be a Player")
	local stat = statByName(name)
	if not stat then
		warn(`[SurvivorCore] Stats.adjust: unknown stat '{name}'`)
		return nil
	end
	local current = player:GetAttribute(stat.attribute)
	current = if typeof(current) == "number" then current else stat.start
	local nextValue = math.clamp(current + delta, 0, stat.max)
	player:SetAttribute(stat.attribute, nextValue)
	return nextValue
end

-- Add (or replace) a named rate modifier on a stat for a player. While active it adds
-- `ratePerSecond` to the stat's effective drift; remove it with removeModifier(source) or
-- let `duration` lapse. Re-adding the same source replaces it (no implicit stacking).
function SurvivalStats.addModifier(player: Player, name: string, spec: ModifierSpec)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Stats.addModifier: player must be a Player")
	assert(
		typeof(spec) == "table" and typeof(spec.ratePerSecond) == "number",
		"Stats.addModifier: spec.ratePerSecond (a number) is required"
	)
	assert(
		typeof(spec.source) == "string" and spec.source ~= "",
		"Stats.addModifier: spec.source (a stable key) is required"
	)
	if not statByName(name) then
		warn(`[SurvivorCore] Stats.addModifier: unknown stat '{name}'`)
		return
	end
	local perPlayer = modifiers[player]
	if not perPlayer then
		perPlayer = {}
		modifiers[player] = perPlayer
	end
	local perStat = perPlayer[name]
	if not perStat then
		perStat = {}
		perPlayer[name] = perStat
	end
	perStat[spec.source] = { ratePerSecond = spec.ratePerSecond, remaining = spec.duration }
end

-- Remove a modifier by its source key (no-op if absent) — an antidote
-- `removeModifier(plr, "Poison", "venom")`, a bandage, or releasing the sprint key.
function SurvivalStats.removeModifier(player: Player, name: string, source: string)
	local perPlayer = modifiers[player]
	local perStat = perPlayer and perPlayer[name]
	if perStat then
		perStat[source] = nil
	end
end

-- Reset every stat to its start value and drop all active modifiers — a fresh body on
-- (re)spawn, so injuries/afflictions don't carry across death (and can't death-loop).
function SurvivalStats.resetPlayer(player: Player)
	if not resolved then
		return
	end
	for _, stat in resolved.stats do
		player:SetAttribute(stat.attribute, stat.start)
	end
	modifiers[player] = nil
end

-- Sum the active modifiers for (player, stat), decrementing timed ones and dropping any
-- that have expired. Returns 0 when the player has none (the common case).
local function sumModifiers(player: Player, name: string, step: number): number
	local perPlayer = modifiers[player]
	local perStat = perPlayer and perPlayer[name]
	if not perStat then
		return 0
	end
	local sum = 0
	for source, mod in perStat do
		sum += mod.ratePerSecond
		if mod.remaining then
			mod.remaining -= step
			if mod.remaining <= 0 then
				perStat[source] = nil
			end
		end
	end
	return sum
end

function SurvivalStats.start(_options: { [string]: any }?)
	assert(not started, "SurvivalStats.start() called twice")
	started = true

	SurvivalStats.installHud()
	refresh()
	watchConfig()

	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end
	Players.PlayerAdded:Connect(initPlayer)
	Players.PlayerRemoving:Connect(function(player)
		modifiers[player] = nil -- drop a leaver's modifiers so the table can't leak
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		if not resolved then
			return
		end
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local step = accumulator
		accumulator = 0

		for _, player in Players:GetPlayers() do
			for _, stat in resolved.stats do
				-- Effective rate = the stat's base drift + any active runtime modifiers
				-- (poison/bleed/sprint/…). sumModifiers also expires timed ones.
				local rate = stat.ratePerSecond + sumModifiers(player, stat.name, step)
				if rate ~= 0 then
					local current = player:GetAttribute(stat.attribute)
					if typeof(current) == "number" then
						local nextValue = math.clamp(current + rate * step, 0, stat.max)
						if nextValue ~= current then
							player:SetAttribute(stat.attribute, nextValue)
						end
					end
				end
			end
		end
	end)
end

return SurvivalStats
