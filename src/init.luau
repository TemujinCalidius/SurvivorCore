--[[
	SurvivorCore — root module.

		local SurvivorCore = require(ReplicatedStorage.SurvivorCore)
		SurvivorCore.Items.register({ id = "reed", name = "Reed" })
		SurvivorCore.start()       -- server: boots content + the survival-stats sim

		-- on the client (the built-in HUD template's loader LocalScript does this):
		SurvivorCore.startClient() -- builds + binds the reactive survival HUD

	Two extension layers:
	  • Programmatic registries (Items, Recipes, Stats, Mobs, ...) — register content from code.
	  • Creator components (tag your own object "Gatherable", set attributes) + lifecycle Hooks.
]]

local Config = require(script.foundation.Config)
local Assets = require(script.foundation.Assets)
local EventBridge = require(script.foundation.EventBridge)
local Hooks = require(script.foundation.Hooks)
local Registries = require(script.registries)
local Components = require(script.components)

-- Eagerly install the built-in survival stats: defines the "SurvivalStats" Config
-- section and registers the default stats, so Config.override("SurvivalStats", …)
-- works any time before start(). Runs on both server and client (idempotent per side).
require(script.stats.StatDefs)

local SurvivorCore = {}

SurvivorCore.VERSION = "0.1.0"

-- Foundation
SurvivorCore.Config = Config
SurvivorCore.Assets = Assets
SurvivorCore.Events = EventBridge
SurvivorCore.Hooks = Hooks

-- Content registries
SurvivorCore.Items = Registries.Items
SurvivorCore.Recipes = Registries.Recipes
SurvivorCore.Stats = Registries.Stats
SurvivorCore.Achievements = Registries.Achievements
SurvivorCore.Codex = Registries.Codex
SurvivorCore.Appearance = Registries.Appearance
SurvivorCore.Mobs = Registries.Mobs

-- Creator-facing component layer
SurvivorCore.Components = Components

local started = false
local clientStarted = false

-- Boot the engine. Call once, from the server, after registering content.
function SurvivorCore.start(_options: { [string]: any }?)
	assert(not started, "SurvivorCore.start() called twice")
	started = true

	-- Load built-in components so their tags are recognised.
	require(script.components.Gatherable)

	-- TODO (extraction): boot order — Config merge → Assets → persistence → systems.
	Components.scan()

	-- Survival-stats simulation (server-only): ticks stats as Player Attributes and
	-- installs the built-in HUD for drop-in consumers that haven't supplied their own.
	require(script.systems.SurvivalStats).start(_options)

	return SurvivorCore
end

-- Boot the client layer. Call once per client — the built-in HUD template's loader
-- LocalScript does this for you. Builds + binds the reactive survival HUD.
function SurvivorCore.startClient(_options: { [string]: any }?)
	if clientStarted then
		warn("[SurvivorCore] startClient() called more than once — ignoring")
		return SurvivorCore
	end
	clientStarted = true

	require(script.client.Hud).start(_options)

	return SurvivorCore
end

return SurvivorCore
