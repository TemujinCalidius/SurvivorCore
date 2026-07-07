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

-- Define the "Mobs" (AI tick/aggro/leash) and "Combat" (melee range/cooldown + bow) Config sections,
-- so Config.override(...) works any time before start()/startClient().
require(script.shared.MobsConfig)
require(script.shared.CombatConfig)

-- Define the "Quests" (max active/toasts) and "Achievements" (toasts) Config sections, so
-- Config.override(...) works any time before start()/startClient().
require(script.shared.QuestsConfig)
require(script.shared.AchievementsConfig)

-- Define the "LootBags" (death-drop) Config section, so Config.override(...) works any time
-- before start().
require(script.shared.LootBagsConfig)

-- The no-code layer over ALL of the sections above: the persisted SurvivorCoreEngineConfig
-- instance (written by the admin plugin, deltas-only). apply() runs as the first step of
-- start()/startClient(), AFTER game-code Config.override calls — the instance wins.
local EngineConfig = require(script.shared.EngineConfig)

local SurvivorCore = {}

SurvivorCore.VERSION = "0.7.4"

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
SurvivorCore.Quests = Registries.Quests
SurvivorCore.Codex = Registries.Codex
SurvivorCore.Appearance = Registries.Appearance
SurvivorCore.Mobs = Registries.Mobs

-- Mob juice: per-mob-type reaction hooks (death fade, spawn cry, hit flinch). Like Gather, safe to
-- register any time; the Mobs FSM dispatches them. SurvivorCore.Mobs.onReaction(id, event, fn) where
-- event = "spawned" | "hit" | "attack" | "died". The runtime API (spawn/adopt/damage/getActive/
-- isMob) is attached after start() (server-only, acts on live mobs).
SurvivorCore.Mobs.onReaction = Reactions.on

-- Creator-facing component layer
SurvivorCore.Components = Components

local started = false
local clientStarted = false

-- Boot the engine. Call once, from the server, after registering content.
function SurvivorCore.start(_options: { [string]: any }?)
	assert(not started, "SurvivorCore.start() called twice")
	started = true

	-- No-code engine tuning: layer the persisted SurvivorCoreEngineConfig instance's deltas onto
	-- every Config section BEFORE anything boots, so systems that cache config at start (and the
	-- ones that read live) all see the same resolved values. Edits apply on the next server start.
	EngineConfig.apply()

	-- No-code content: register item/resource defs authored as instances (the admin plugin writes
	-- these under ReplicatedStorage.SurvivorCoreContent), complementing code register(). Done first,
	-- so Gatherable nodes can resolve their Resource def and systems see the full roster. Recipes
	-- carry ingredient lists (not flat attributes), so they stay code-registered for now.
	local content = ReplicatedStorage:FindFirstChild("SurvivorCoreContent")
	if content then
		Registries.Items.loadFromFolder(content:FindFirstChild("Items"))
		-- Weapons and Arrows ARE items (category = "weapon" / "ammo"); the admin plugin authors them in
		-- their own folders so its editors don't collide with the Items editor — load both into Items.
		Registries.Items.loadFromFolder(content:FindFirstChild("Weapons"))
		Registries.Items.loadFromFolder(content:FindFirstChild("Arrows"))
		Registries.Resources.loadFromFolder(content:FindFirstChild("Resources"))
		Registries.Mobs.loadFromFolder(content:FindFirstChild("Mobs"))
		-- Quests are flat single-objective defs no-code (QuestData.normalize reads them);
		-- achievement defs are flat by design, so they load verbatim.
		Registries.Quests.loadFromFolder(content:FindFirstChild("Quests"))
		Registries.Achievements.loadFromFolder(content:FindFirstChild("Achievements"))

		-- Owner overrides (issue #40): SurvivorCoreContent/Overrides mirrors the folders above and
		-- field-merges deltas onto ALREADY-registered defs — including code-registered ones, which
		-- the folders themselves can't touch (loadFromFolder skips existing keys). Applied here,
		-- before Components.scan and system starts, so bind-time stamps and the replicated data
		-- caches (ItemData/RecipeData/QuestData/AchievementData) all serialize the merged defs.
		local overrides = content:FindFirstChild("Overrides")
		if overrides then
			Registries.Items.applyOverrides(overrides:FindFirstChild("Items"))
			Registries.Items.applyOverrides(overrides:FindFirstChild("Weapons"))
			Registries.Items.applyOverrides(overrides:FindFirstChild("Arrows"))
			Registries.Resources.applyOverrides(overrides:FindFirstChild("Resources"))
			Registries.Mobs.applyOverrides(overrides:FindFirstChild("Mobs"))
			Registries.Quests.applyOverrides(overrides:FindFirstChild("Quests"))
			Registries.Achievements.applyOverrides(overrides:FindFirstChild("Achievements"))

			-- Quest-override caveat, made LOUD: QuestData.normalize prefers a def's nested
			-- objectives/rewards tables, so flat objective*/reward* override fields silently do
			-- nothing on a code-registered quest that uses the canonical nested shape. The id
			-- matched, so applyOverrides' typo warning didn't fire — surface it here instead.
			local questOverrides = overrides:FindFirstChild("Quests")
			if questOverrides then
				for _, child in questOverrides:GetChildren() do
					local def = Registries.Quests.get(child.Name)
					if def and typeof(def.objectives) == "table" then
						for attr in child:GetAttributes() do
							if string.match(attr, "^objective") or string.match(attr, "^reward") then
								warn(
									`[SurvivorCore] quest override '{child.Name}': objective*/reward* fields are`
										.. " ignored for code quests with nested objectives — only name/description/"
										.. "autoStart/requires/turnIn merge"
								)
								break
							end
						end
					end
				end
			end
		end
	end

	-- Load built-in components so their tags are recognised.
	require(script.components.Gatherable)
	require(script.components.Mob)
	require(script.components.QuestGiver)

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

	-- Mobs: the shared mob & AI engine (FSM substrate). Adopts any "Mob"-tagged model (done during
	-- Components.scan above) and runs its AI; the runtime API acts on live mobs, so it's attached
	-- here after start(): SurvivorCore.Mobs.spawn(type, cframe, opts) / adopt / damage / getActive /
	-- isMob (registry register/get/getAll/query + onReaction were available before start()).
	local mobs = require(script.systems.Mobs)
	mobs.start(_options)
	SurvivorCore.Mobs.spawn = mobs.spawn
	SurvivorCore.Mobs.adopt = mobs.adopt
	SurvivorCore.Mobs.damage = mobs.damage
	SurvivorCore.Mobs.getActive = mobs.getActive
	SurvivorCore.Mobs.isMob = mobs.isMob

	-- Combat: server-authoritative melee + ranged (bow). Booted after Inventory (bow ammo) and Mobs
	-- (its targets). Reuses the tool-swing pipeline; fires the combat:hit / combat:kill schema.
	local combat = require(script.systems.Combat)
	combat.start(_options)
	SurvivorCore.Combat = combat

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

	-- Progression: the ONE event → (kind, target, amount) translation layer quests and
	-- achievements consume. Exposed so games can map their own events:
	--   SurvivorCore.Progression.map("myEvent", function(player, data) return "kill", "boss", 1 end)
	local progression = require(script.systems.Progression)
	progression.start(_options)
	SurvivorCore.Progression = progression

	-- Quests: accept → progress → complete → reward (issue #10). Runtime ops attach onto the
	-- registry table (register/getAll were available before start; these act on live players):
	--   SurvivorCore.Quests.accept(player, "gather_reeds")
	local quests = require(script.systems.Quests)
	quests.start(_options)
	SurvivorCore.Quests.accept = quests.accept
	SurvivorCore.Quests.complete = quests.complete
	SurvivorCore.Quests.abandon = quests.abandon
	SurvivorCore.Quests.getLog = quests.getLog
	SurvivorCore.Quests.isActive = quests.isActive
	SurvivorCore.Quests.isCompleted = quests.isCompleted

	-- Achievements: always-on counters → threshold → unlock-once (+ toast). Same attach pattern:
	--   SurvivorCore.Achievements.award(player, "secret_cave")
	local achievements = require(script.systems.Achievements)
	achievements.start(_options)
	SurvivorCore.Achievements.award = achievements.award
	SurvivorCore.Achievements.addCount = achievements.addCount
	SurvivorCore.Achievements.isUnlocked = achievements.isUnlocked
	SurvivorCore.Achievements.getState = achievements.getState

	-- LootBags: death drops the player's belongings into a lootable bag (+ player:died lifecycle,
	-- deaths counters). Booted after Inventory (snapshot/clear APIs) and Progression (death map).
	local lootBags = require(script.systems.LootBags)
	lootBags.start(_options)
	SurvivorCore.LootBags = lootBags

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

	-- Same no-code tuning layer as the server (idempotent per VM; the client cares about the UI
	-- section — theme, keybinds, layout — which the client-side builders read at start).
	EngineConfig.apply()

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

	-- Goals & progression: toast notifications + the Quests and Achievements tabs (they adopt the
	-- menu template's scaffolded panels).
	require(script.client.Toasts).start(_options)
	require(script.client.QuestsUi).start(_options)
	require(script.client.AchievementsUi).start(_options)

	-- Death & respawn juice: keep the camera on the new body, and beacon the owner's loot bag.
	require(script.client.RespawnCamera).start(_options)
	require(script.client.LootBagBeacon).start(_options)

	-- Tool-swing harvesting input (click an equipped tool at a gatherable node).
	require(script.client.ToolHarvest).start(_options)

	-- Combat input (click an equipped weapon: melee swing, or hold-to-draw a bow). Routes by the
	-- held Tool's WeaponKind, so it coexists with ToolHarvest without double-firing.
	require(script.client.CombatInput).start(_options)

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
