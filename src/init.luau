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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.foundation.Config)
local Assets = require(script.foundation.Assets)
local EventBridge = require(script.foundation.EventBridge)
local Hooks = require(script.foundation.Hooks)
local Reactions = require(script.foundation.Reactions)
local Registries = require(script.registries)
local Components = require(script.components)

-- Eagerly install the built-in survival stats: defines the "SurvivalStats" Config
-- section and registers the default stats, so Config.override("SurvivalStats", …)
-- works any time before start(). Runs on both server and client (idempotent per side).
require(script.stats.StatDefs)

-- Define the "Movement" Config section (sprint/jump/energy + feedback tuning) on both
-- sides, so Config.override("Movement", …) works any time before start()/startClient().
require(script.shared.MovementConfig)

-- Define the "Consequences" Config section (stat → health-drain tuning), so
-- Config.override("Consequences", …) works any time before start().
require(script.shared.ConsequenceConfig)

-- Define the "Inventory" Config section (slots + carry-weight + hotbar + equip-slot tuning),
-- so Config.override("Inventory", …) works any time before start().
require(script.shared.InventoryConfig)

-- Define the "UI" Config section (menu/hotbar theme + keybinds), so
-- Config.override("UI", …) works any time before startClient().
require(script.shared.UiConfig)

-- Define the "Harvesting" (tool-swing range/cooldown/LoS) and "Crafting" (craft time) Config
-- sections, so Config.override(...) works any time before start()/startClient().
require(script.shared.HarvestingConfig)
require(script.shared.CraftingConfig)

local SurvivorCore = {}

SurvivorCore.VERSION = "0.3.0"

-- Foundation
SurvivorCore.Config = Config
SurvivorCore.Assets = Assets
SurvivorCore.Events = EventBridge
SurvivorCore.Hooks = Hooks

-- Gathering juice: per-resource-type reaction hooks (shake / fell / etc.). Registration is safe
-- any time; the harvesting path dispatches them. SurvivorCore.Gather.onReaction(id, event, fn).
SurvivorCore.Gather = { onReaction = Reactions.on }

-- Content registries
SurvivorCore.Items = Registries.Items
SurvivorCore.Recipes = Registries.Recipes
SurvivorCore.Resources = Registries.Resources
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

	-- No-code content: register item/resource defs authored as instances (the admin plugin writes
	-- these under ReplicatedStorage.SurvivorCoreContent), complementing code register(). Done first,
	-- so Gatherable nodes can resolve their Resource def and systems see the full roster. Recipes
	-- carry ingredient lists (not flat attributes), so they stay code-registered for now.
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	if content then
		Registries.Items.loadFromFolder(content:FindFirstChild("Items"))
		Registries.Resources.loadFromFolder(content:FindFirstChild("Resources"))
	end

	-- Load built-in components so their tags are recognised.
	require(script.components.Gatherable)

	-- TODO (extraction): boot order — Config merge → Assets → persistence → systems.
	Components.scan()

	-- Survival-stats simulation (server-only): ticks stats as Player Attributes and
	-- installs the built-in HUD for drop-in consumers that haven't supplied their own.
	local survival = require(script.systems.SurvivalStats)
	survival.start(_options)

	-- Runtime stat operations become available once the sim is running. They act on live
	-- players, so they're server-only (exposed here after start, not at require time):
	--   SurvivorCore.Stats.adjust(player, "Poison", 1)              -- one-time delta
	--   SurvivorCore.Stats.addModifier(player, "Poison", {ratePerSecond = 2, source = "venom"})
	--   SurvivorCore.Stats.removeModifier(player, "Poison", "venom")
	--   SurvivorCore.Stats.getValue(player, "Energy")
	SurvivorCore.Stats.adjust = survival.adjust
	SurvivorCore.Stats.addModifier = survival.addModifier
	SurvivorCore.Stats.removeModifier = survival.removeModifier
	SurvivorCore.Stats.getValue = survival.getValue

	-- Movement: server-authoritative sprint/jump/energy (creates the SprintIntent RemoteEvent).
	require(script.systems.Movement).start(_options)

	-- Consequences: stats bite back (starve/dehydrate/poison/bleed → health → death) + the
	-- Health↔Humanoid sync and fresh-body reset on respawn.
	require(script.systems.SurvivalConsequences).start(_options)

	-- Inventory: server-authoritative slots + carry-weight, hotbar, equipment, consumables.
	-- Booted after SurvivalStats so consumables apply their effects via Stats.adjust. The
	-- module table IS the public API — SurvivorCore.Inventory.add/remove/move/split/equip/
	-- unequip/setHotbar/swapHotbar/useSlot/getQty/has/getSlots (all act on live players).
	local inventory = require(script.systems.Inventory)
	inventory.start(_options)
	SurvivorCore.Inventory = inventory

	-- ToolEquip: hotbar → physical Tool bridge (an active tool item becomes a held Roblox Tool).
	require(script.systems.ToolEquip).start(_options)

	-- Harvesting: the authoritative hit resolver for gatherable nodes (prompt + tool-swing). Booted
	-- after Inventory so per-hit yield can be granted (and a full inventory blocks the hit). The
	-- module table exposes tryHarvest, which the Gatherable component's prompt path calls in.
	local harvesting = require(script.systems.Harvesting)
	harvesting.start(_options)
	SurvivorCore.Harvesting = harvesting

	-- Crafting: server-authoritative hand crafting (consume recipe ingredients → produce output).
	local crafting = require(script.systems.Crafting)
	crafting.start(_options)
	SurvivorCore.Crafting = crafting

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

	-- Sprint input + low-stat vignette/breathing/heartbeat feedback.
	require(script.client.MovementFeedback).start(_options)

	-- UI layer: the tabbed menu (Inventory / Character / scaffolded Codex·Achievements·Quests)
	-- and the bottom hotbar — authored ScreenGui templates driven by attribute binders, exactly
	-- like the HUD. PanelManager owns the menu + keybind; SurvivorCore.UI exposes its registrable
	-- panel API (registerPanel / open / close / toggle).
	require(script.client.DragDrop).start(_options)
	local panelManager = require(script.client.PanelManager)
	panelManager.start(_options)
	SurvivorCore.UI = panelManager
	require(script.client.Hotbar).start(_options)
	require(script.client.InventoryUi).start(_options)
	require(script.client.CharacterSheet).start(_options)
	require(script.client.CraftingUi).start(_options)

	-- Tool-swing harvesting input (click an equipped tool at a gatherable node).
	require(script.client.ToolHarvest).start(_options)

	-- Zero-setup net: if no authored menu/hotbar template reached the player, build the minimal
	-- fallback (the binders pick it up via DescendantAdded, like HudFallback).
	task.delay(2, function()
		local localPlayer = game:GetService("Players").LocalPlayer
		local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
		if not playerGui then
			return
		end
		local UiFallback = require(script.client.UiFallback)
		if not playerGui:FindFirstChild("SurvivalMenu") then
			UiFallback.buildMenu(playerGui)
		end
		if not playerGui:FindFirstChild("SurvivalHotbar") then
			UiFallback.buildHotbar(playerGui)
		end
	end)

	return SurvivorCore
end

return SurvivorCore
