--!nonstrict
--[[
	EngineConfig — the no-code layer over EVERY engine Config section (issue #21). SHARED.

	Owners tune the engine without code via ONE persisted instance:

		ReplicatedStorage.SurvivorCoreEngineConfig            (Configuration)
		├─ Movement (Configuration)
		│   └─ Energy / Movement / Health / Audio / Assets    (Configurations; attributes = fields)
		├─ Combat (Configuration; root attributes)  └─ Bow    (Configuration)
		└─ …one child per section, one grandchild per nested group…

	The instance holds ONLY overridden fields (deltas — the admin plugin removes an attribute the
	moment it equals the engine default), so unset fields keep following engine defaults across
	updates. Resolution order: engine defaults (defineSection at require) → game
	`Config.override(...)` → this instance (HIGHEST priority, applied by `EngineConfig.apply()` as
	the first step of `SurvivorCore.start()` / `startClient()`). Apply-once at boot: edits take
	effect on the NEXT Play/server start (several systems cache their section at start, so a live
	watch would only half-apply — this contract is honest).

	`EngineConfig.SECTIONS` is the schema the admin plugin renders (sections → groups → typed
	fields) and the allow-list `apply()` walks — plugin and engine can never disagree. Field kinds:
	number | boolean | string | enum | color3 (native Color3 attribute) | font (attribute holds an
	Enum.Font NAME, e.g. "GothamMedium"). Invalid saved values are warned about and SKIPPED — a bad
	attribute must never break boot. SurvivalStats is deliberately absent (it has its own locked
	instance + editor; see StatConfig).
]]

local Config = require(script.Parent.Parent.foundation.Config)

local MovementConfig = require(script.Parent.MovementConfig)
local ConsequenceConfig = require(script.Parent.ConsequenceConfig)
local InventoryConfig = require(script.Parent.InventoryConfig)
local UiConfig = require(script.Parent.UiConfig)
local HarvestingConfig = require(script.Parent.HarvestingConfig)
local CraftingConfig = require(script.Parent.CraftingConfig)
local MobsConfig = require(script.Parent.MobsConfig)
local CombatConfig = require(script.Parent.CombatConfig)
local QuestsConfig = require(script.Parent.QuestsConfig)
local AchievementsConfig = require(script.Parent.AchievementsConfig)
local LootBagsConfig = require(script.Parent.LootBagsConfig)

local EngineConfig = {}

EngineConfig.INSTANCE_NAME = "SurvivorCoreEngineConfig"

export type Field = {
	attr: string,
	kind: string, -- "number" | "boolean" | "string" | "enum" | "color3" | "font"
	label: string,
	min: number?,
	max: number?,
	integer: boolean?,
	choices: { string }?,
	check: string?, -- "keycode" | "assetId"
	note: string?,
}

export type Group = {
	name: string?, -- nil = attributes live on the section child itself
	label: string,
	fields: { Field },
}

export type Section = {
	id: string, -- Config section name AND instance child name
	title: string,
	note: string?, -- rendered by the plugin as a dim note row (e.g. code-managed fields)
	groups: { Group },
}

local function num(attr: string, label: string, min: number?, max: number?, integer: boolean?): Field
	return { attr = attr, kind = "number", label = label, min = min, max = max, integer = integer }
end

local function boolean(attr: string, label: string): Field
	return { attr = attr, kind = "boolean", label = label }
end

local function color(attr: string, label: string): Field
	return { attr = attr, kind = "color3", label = label }
end

EngineConfig.SECTIONS = {
	{
		id = "Movement",
		title = "Movement",
		groups = {
			{
				name = "Movement",
				label = "Speeds",
				fields = {
					num("WalkSpeed", "Walk speed", 0),
					num("SprintSpeed", "Sprint speed", 0),
					num("ExhaustedSpeed", "Exhausted speed", 0),
					num("JumpPower", "Jump power", 0),
				},
			},
			{
				name = "Energy",
				label = "Energy",
				fields = {
					num("Max", "Max energy", 1),
					num("SprintDrainPerSecond", "Sprint drain / s", 0),
					num("JumpCost", "Jump cost", 0),
					num("RegenPerSecond", "Regen / s", 0),
					num("RegenDelaySeconds", "Regen delay (s)", 0),
					num("MinToJump", "Min energy to jump", 0),
				},
			},
			{
				name = "Health",
				label = "Health feedback",
				fields = {
					num("HeartbeatStartRatio", "Heartbeat starts at (0-1)", 0, 1),
				},
			},
			{
				name = "Audio",
				label = "Audio feedback",
				fields = {
					num("BreathingMaxVolume", "Breathing max volume", 0, 10),
					num("BreathingMinSpeed", "Breathing min speed", 0.05),
					num("BreathingMaxSpeed", "Breathing max speed", 0.05),
					num("HeartbeatMaxVolume", "Heartbeat max volume", 0, 10),
					num("HeartbeatMinSpeed", "Heartbeat min speed", 0.05),
					num("HeartbeatMaxSpeed", "Heartbeat max speed", 0.05),
				},
			},
			{
				name = "Assets",
				label = "Assets (rbxassetid://…)",
				fields = {
					{ attr = "Vignette", kind = "string", label = "Low-stat vignette", check = "assetId" },
					{ attr = "Breathing", kind = "string", label = "Breathing sound", check = "assetId" },
					{ attr = "Heartbeat", kind = "string", label = "Heartbeat sound", check = "assetId" },
				},
			},
		},
	},
	{
		id = "Combat",
		title = "Combat",
		groups = {
			{
				label = "Melee",
				fields = {
					num("MeleeRange", "Melee range (studs)", 0.5),
					num("MeleeCooldown", "Melee cooldown (s)", 0),
					boolean("RequireLineOfSight", "Require line of sight"),
					boolean("FriendlyFire", "Friendly fire"),
				},
			},
			{
				name = "Bow",
				label = "Bow & arrows",
				fields = {
					num("Gravity", "Arrow gravity", 0),
					num("ProjectileSpeed", "Projectile speed", 1),
					num("MaxRange", "Max range (studs)", 1),
					num("MinDrawDamageMult", "Min-draw damage mult (0-1)", 0, 1),
					num("StepSize", "Sim step size (studs)", 1),
				},
			},
		},
	},
	{
		id = "Mobs",
		title = "Mobs & AI",
		groups = {
			{
				label = "AI defaults",
				fields = {
					num("TickRate", "AI tick rate (s)", 0.05),
					num("DefaultAggroRange", "Aggro range", 0),
					num("DefaultLeashRange", "Leash range", 0),
					num("DefaultAttackRange", "Attack range", 0),
					num("DefaultAttackDamage", "Attack damage", 0),
					num("DefaultAttackCooldown", "Attack cooldown (s)", 0),
					num("DefaultWanderRadius", "Wander radius", 0),
					boolean("RequireLineOfSight", "Require line of sight"),
					num("RespawnSeconds", "Respawn after (s)", 0),
					num("CorpseSeconds", "Corpse lingers (s)", 0),
					num("DefaultCarcassSeconds", "Carcass lingers (s)", 0),
				},
			},
		},
	},
	{
		id = "Harvesting",
		title = "Harvesting",
		groups = {
			{
				label = "Tool swings",
				fields = {
					num("SwingRange", "Swing range (studs)", 0.5),
					num("SwingCooldown", "Swing cooldown (s)", 0),
					boolean("RequireLineOfSight", "Require line of sight"),
					boolean("ShowHealthBar", "Show node health bar"),
				},
			},
		},
	},
	{
		id = "Crafting",
		title = "Crafting",
		groups = {
			{
				label = "Craft times",
				fields = {
					num("BaseCraftTime", "Base craft time (s)", 0),
					num("TimePerIngredient", "Time per ingredient (s)", 0),
					num("MaxCraftTime", "Max craft time (s)", 0.1),
				},
			},
		},
	},
	{
		id = "Inventory",
		title = "Inventory",
		note = 'Equip slots & auto-hotbar categories are lists — set them from code via Config.override("Inventory", …).',
		groups = {
			{
				label = "Capacity & hotbar",
				fields = {
					num("BasePocketSlots", "Base pocket slots", 1, nil, true),
					num("BasePocketWeight", "Base carry weight", 0),
					num("HotbarSize", "Hotbar slots", 1, 9, true),
					num("UseCooldownSeconds", "Item-use cooldown (s)", 0),
				},
			},
		},
	},
	{
		id = "Consequences",
		title = "Consequences",
		groups = {
			{
				name = "HealthDrainPerSecond",
				label = "Health drain / s",
				fields = {
					num("Starving", "While starving", 0),
					num("Dehydrated", "While dehydrated", 0),
					num("PoisonAtMax", "At max poison", 0),
				},
			},
			{
				name = "Affliction",
				label = "Affliction build-up / s",
				fields = {
					num("BleedRatePerSecond", "Bleed rate", 0),
					num("PoisonRatePerSecond", "Poison rate", 0),
				},
			},
		},
	},
	{
		id = "LootBags",
		title = "Loot bags",
		groups = {
			{
				label = "Death drops",
				fields = {
					boolean("Enabled", "Drop a bag on death"),
					boolean("DropEquipment", "Drop worn equipment too"),
					num("LifetimeSeconds", "Bag lifetime (s)", 1),
					num("InteractRange", "Loot prompt range (studs)", 1),
					boolean("ShowCountdown", "Show countdown"),
					boolean("OwnerBeacon", "Owner beacon"),
				},
			},
		},
	},
	{
		id = "Quests",
		title = "Quests",
		groups = {
			{
				label = "Quests",
				fields = {
					num("MaxActive", "Max active (0 = unlimited)", 0, nil, true),
					boolean("Toasts", "Completion toasts"),
				},
			},
		},
	},
	{
		id = "Achievements",
		title = "Achievements",
		groups = {
			{
				label = "Achievements",
				fields = {
					boolean("Toasts", "Unlock toasts"),
				},
			},
		},
	},
	{
		id = "UI",
		title = "UI & theme",
		groups = {
			{
				label = "General",
				fields = {
					boolean("ReclaimCoreKeys", "Reclaim core Roblox keys"),
					num("DragThreshold", "Drag threshold (px)", 0),
				},
			},
			{
				name = "Keybinds",
				label = "Keybinds (Enum.KeyCode names)",
				fields = {
					{ attr = "Menu", kind = "string", label = "Menu", check = "keycode" },
					{ attr = "Character", kind = "string", label = "Character", check = "keycode" },
					{ attr = "Codex", kind = "string", label = "Codex", check = "keycode" },
					{ attr = "Achievements", kind = "string", label = "Achievements", check = "keycode" },
					{ attr = "Quests", kind = "string", label = "Quests", check = "keycode" },
				},
			},
			{
				name = "Chat",
				label = "Chat placement",
				fields = {
					boolean("Reposition", "Reposition chat"),
					{
						attr = "Horizontal",
						kind = "enum",
						label = "Horizontal",
						choices = { "Left", "Center", "Right" },
					},
					{ attr = "Vertical", kind = "enum", label = "Vertical", choices = { "Top", "Center", "Bottom" } },
				},
			},
			{
				name = "Theme",
				label = "Theme",
				fields = {
					color("PanelColor", "Panel color"),
					num("PanelTransparency", "Panel transparency (0-1)", 0, 1),
					color("SlotColor", "Slot color"),
					num("CornerRadius", "Corner radius", 0, nil, true),
					color("StrokeColor", "Stroke color"),
					num("StrokeTransparency", "Stroke transparency (0-1)", 0, 1),
					color("Text", "Text color"),
					color("TextSecondary", "Secondary text color"),
					color("Accent", "Accent color"),
					color("Bad", "Bad/danger color"),
					color("Ok", "Ok/good color"),
					{ attr = "Font", kind = "font", label = "Font" },
					{ attr = "FontBold", kind = "font", label = "Bold font" },
				},
			},
			{
				name = "Inventory",
				label = "Inventory grid",
				fields = {
					num("SlotSize", "Slot size (px)", 8),
					num("SlotPadding", "Slot padding (px)", 0),
					num("Columns", "Columns", 1, nil, true),
				},
			},
			{
				name = "Hotbar",
				label = "Hotbar",
				fields = {
					num("SlotSize", "Slot size (px)", 8),
					num("SlotPadding", "Slot padding (px)", 0),
				},
			},
			{
				name = "DisplayOrder",
				label = "Display order (z-layers)",
				fields = {
					num("Menu", "Menu", nil, nil, true),
					num("Hotbar", "Hotbar", nil, nil, true),
					num("ClickOutside", "Click-outside shield", nil, nil, true),
					num("DragGhost", "Drag ghost", nil, nil, true),
				},
			},
		},
	},
}

local DEFAULTS_BY_SECTION: { [string]: any } = {
	Movement = MovementConfig.DEFAULTS,
	Combat = CombatConfig.DEFAULTS,
	Mobs = MobsConfig.DEFAULTS,
	Harvesting = HarvestingConfig.DEFAULTS,
	Crafting = CraftingConfig.DEFAULTS,
	Inventory = InventoryConfig.DEFAULTS,
	Consequences = ConsequenceConfig.DEFAULTS,
	LootBags = LootBagsConfig.DEFAULTS,
	Quests = QuestsConfig.DEFAULTS,
	Achievements = AchievementsConfig.DEFAULTS,
	UI = UiConfig.DEFAULTS,
}

local function deepCopy(t: any): any
	if typeof(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

-- The engine defaults for one section (deep copy — safe for the plugin to display/compare).
function EngineConfig.getDefaults(sectionId: string): any
	local defaults = DEFAULTS_BY_SECTION[sectionId]
	return if defaults then deepCopy(defaults) else nil
end

-- Validate + convert one saved attribute value per its field spec. Returns (ok, value?, err?).
local function resolveValue(field: Field, raw: any): (boolean, any, string?)
	if field.kind == "number" then
		if typeof(raw) ~= "number" then
			return false, nil, "expected a number"
		end
		if raw ~= raw or raw == math.huge or raw == -math.huge then
			return false, nil, "expected a finite number"
		end
		local v = raw
		if field.min then
			v = math.max(v, field.min)
		end
		if field.max then
			v = math.min(v, field.max)
		end
		if field.integer then
			v = math.floor(v + 0.5)
		end
		return true, v
	elseif field.kind == "boolean" then
		if typeof(raw) ~= "boolean" then
			return false, nil, "expected a boolean"
		end
		return true, raw
	elseif field.kind == "string" then
		if typeof(raw) ~= "string" then
			return false, nil, "expected a string"
		end
		if field.check == "keycode" then
			local ok, keyCode = pcall(function()
				return (Enum.KeyCode :: any)[raw]
			end)
			if not ok or typeof(keyCode) ~= "EnumItem" then
				return false, nil, `'{raw}' is not an Enum.KeyCode name`
			end
		elseif field.check == "assetId" then
			if raw ~= "" and string.match(raw, "^rbxassetid://%d+$") == nil then
				-- Accept but call it out — creators sometimes paste other valid content URIs.
				warn(`[SurvivorCore.EngineConfig] '{field.attr}' = '{raw}' doesn't look like rbxassetid://<id>`)
			end
		end
		return true, raw
	elseif field.kind == "enum" then
		if typeof(raw) ~= "string" then
			return false, nil, "expected a string"
		end
		local choices: { string } = field.choices or {}
		for _, choice in choices do
			if choice == raw then
				return true, raw
			end
		end
		return false, nil, `'{raw}' is not one of: {table.concat(choices, ", ")}`
	elseif field.kind == "color3" then
		if typeof(raw) ~= "Color3" then
			return false, nil, "expected a Color3"
		end
		return true, raw
	elseif field.kind == "font" then
		if typeof(raw) ~= "string" then
			return false, nil, "expected an Enum.Font name"
		end
		local ok, font = pcall(function()
			return (Enum.Font :: any)[raw]
		end)
		if not ok or typeof(font) ~= "EnumItem" then
			return false, nil, `'{raw}' is not an Enum.Font name`
		end
		return true, font
	end
	return false, nil, `unknown field kind '{field.kind}'`
end

-- Read the persisted instance (if any) and layer its deltas onto every section via
-- Config.override. Call once, before systems boot, on BOTH server and client. Invalid values
-- warn and are skipped — never fatal. Returns counts for testing.
function EngineConfig.apply(): { sections: number, fields: number, warnings: { string } }
	local result = { sections = 0, fields = 0, warnings = {} }
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local instance = ReplicatedStorage:FindFirstChild(EngineConfig.INSTANCE_NAME)
	if not instance then
		return result
	end

	for _, section in EngineConfig.SECTIONS do
		local sectionChild = instance:FindFirstChild(section.id)
		if not sectionChild then
			continue
		end
		local overrides: { [string]: any } = {}
		local sectionFields = 0
		for _, group in section.groups do
			local node: Instance? = if group.name then sectionChild:FindFirstChild(group.name) else sectionChild
			if not node then
				continue
			end
			for _, field in group.fields do
				local raw = node:GetAttribute(field.attr)
				if raw == nil then
					continue
				end
				local ok, value, err = resolveValue(field, raw)
				if not ok then
					local path = `{section.id}{if group.name then "." .. group.name else ""}.{field.attr}`
					local message = `[SurvivorCore.EngineConfig] ignoring '{path}': {err}`
					warn(message)
					table.insert(result.warnings, message)
					continue
				end
				if group.name then
					local sub = overrides[group.name]
					if sub == nil then
						sub = {}
						overrides[group.name] = sub
					end
					sub[field.attr] = value
				else
					overrides[field.attr] = value
				end
				sectionFields += 1
			end
		end
		if sectionFields > 0 then
			Config.override(section.id, overrides)
			result.sections += 1
			result.fields += sectionFields
		end
	end

	return result
end

return EngineConfig
