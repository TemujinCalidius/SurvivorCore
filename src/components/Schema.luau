--!nonstrict
--[[
	Component schemas — the PURE description of every creator component: what attributes it reads,
	their kind/default/help/options, and how a builder UI should present it.

	This module has NO dependencies, on purpose. The Studio plugin requires it LIVE at edit time
	(ReplicatedStorage.SurvivorCore.components.Schema), exactly as the plugin's Engine Config editor
	requires shared/EngineConfig — so the plugin and the engine can never disagree about a
	component's fields. Requiring a component module instead is NOT an option: those pull in server
	systems (Harvesting asserts IsServer at module scope; Remotes CREATES instances in
	ReplicatedStorage), which would throw or pollute the creator's place file in Edit mode.

	Attribute names here are PascalCase INSTANCE attributes (`ItemId`, `HP`) — a different namespace
	from the lowercase registry-def fields the Content editor writes (`item`, `hp`). Never mix them:
	a def says what "oak_tree" IS; an instance attribute says what THIS part is (or which def it
	inherits from).

	Attributes beginning with "_" are ENGINE-INTERNAL (the `_scBound` bind marker, Gatherable's
	resolved `_ItemId`/`_HP`/… stamps). They are never authored, never shown, and are cleared when
	a builder untags an instance.
]]

local Schema = {}

-- Bumped when the shape changes. Readers must tolerate unknown fields and unknown `kind`s.
Schema.VERSION = 1

export type AttributeSpec = {
	attr: string, -- PascalCase instance Attribute name
	kind: string, -- "number" | "boolean" | "string" | "enum" (unknown kinds render as text)
	label: string,
	default: any, -- MUST equal the value the component's onSetup assumes
	help: string?, -- one sentence shown under the field
	choices: { string }?, -- kind == "enum"
	min: number?,
	max: number?,
	integer: boolean?,
	placeholder: string?,
	group: string?, -- form section header; first-appearance order wins. nil = "Settings"
	ref: string?, -- names a content category ("Items"/"Resources"/"Mobs"/"Quests") whose authored
	-- ids a builder can offer as a picker. A UI hint only — the engine ignores it.
	advanced: boolean?, -- hidden behind "show advanced" (legacy / rarely-set fields)
}

export type Display = {
	title: string, -- chooser card title
	summary: string, -- one line: what this component makes the object do
	instance: string?, -- "BasePart" | "Model" | "any" (default "any") — chooser eligibility
	icon: string?, -- reserved (rbxassetid://…)
	order: number?, -- chooser sort; ties break on title
	hint: string?, -- shown above the form
}

export type ComponentSchema = {
	name: string,
	tag: string,
	display: Display,
	attributes: { AttributeSpec },
}

-- ── Normalisation (accepts the legacy shorthand as well as the schema form) ───

-- "ItemId" -> "Item Id". Only used for LEGACY map-form attributes, which declare no label.
local function humanize(attr: string): string
	return (string.gsub(attr, "(%l)(%u)", "%1 %2"))
end

local function inferKind(default: any): string
	local t = typeof(default)
	return if t == "number" then "number" elseif t == "boolean" then "boolean" else "string"
end

-- Always returns an ORDERED array of AttributeSpec, from either form:
--   schema:  { { attr = "HP", kind = "number", … }, … }   (array — attributes[1] ~= nil)
--   legacy:  { HP = 0, ItemId = "" }                       (map — sorted, since `pairs` order is
--                                                           arbitrary and would make a UI jitter)
function Schema.normalize(attributes: any?): { AttributeSpec }
	if attributes == nil then
		return {}
	end
	if (attributes :: any)[1] ~= nil then
		for _, spec in attributes :: { AttributeSpec } do
			assert(typeof(spec.attr) == "string", "component attribute spec needs `attr`")
		end
		return attributes :: { AttributeSpec }
	end
	local out: { AttributeSpec } = {}
	for attr, default in attributes :: { [string]: any } do
		table.insert(out, { attr = attr, kind = inferKind(default), label = humanize(attr), default = default })
	end
	table.sort(out, function(a, b)
		return a.attr < b.attr
	end)
	return out
end

-- attr -> default map: exactly what the legacy `attributes` table was, so binding is unchanged.
function Schema.defaults(attributes: { AttributeSpec }): { [string]: any }
	local out = {}
	for _, spec in attributes do
		out[spec.attr] = spec.default
	end
	return out
end

-- ── The shipped component schemas ────────────────────────────────────────────
-- Defaults are copied VERBATIM from each component's original attribute table: they are behaviour,
-- not decoration (Gatherable's resolve() reads "" / 0 as "inherit from the resource def").

local INHERIT_ZERO = "0 = inherit the mob def, then the Mobs config."

Schema.COMPONENTS = {
	Gatherable = {
		name = "Gatherable",
		tag = "Gatherable",
		display = {
			title = "Gatherable",
			summary = "A tree, rock or bush players harvest for items.",
			instance = "any",
			order = 1,
			hint = "Point it at a Gatherables entry (easiest) — or leave that blank and set the item,"
				.. " HP and yield by hand. Blank / 0 fields follow the entry.",
		},
		attributes = {
			{
				attr = "Resource",
				kind = "string",
				label = "Resource",
				default = "",
				ref = "Resources",
				placeholder = "a Gatherables id",
				group = "What it is",
				help = "Inherit item, HP, tool and yield from a Content › Gatherables entry.",
			},
			{
				attr = "ItemId",
				kind = "string",
				label = "Item yielded",
				default = "",
				ref = "Items",
				group = "What it is",
				help = "Overrides the resource's item. Blank = use the resource.",
			},
			{
				attr = "HP",
				kind = "number",
				label = "HP (hits to deplete)",
				default = 0,
				min = 0,
				integer = true,
				group = "Harvesting",
				help = "0 = inherit the resource (or 3).",
			},
			{
				attr = "RequireTool",
				kind = "string",
				label = "Tool required",
				default = "",
				placeholder = "axe / pickaxe",
				group = "Harvesting",
				help = "Blank = bare hands (hold-E). Set a tool type to make it click-to-swing.",
			},
			{
				attr = "YieldMin",
				kind = "number",
				label = "Yield min",
				default = 0,
				min = 0,
				integer = true,
				group = "Harvesting",
				help = "Items per hit, low end. 0 = inherit the resource.",
			},
			{
				attr = "YieldMax",
				kind = "number",
				label = "Yield max",
				default = 0,
				min = 0,
				integer = true,
				group = "Harvesting",
				help = "Items per hit, high end. 0 = inherit the resource.",
			},
			{
				attr = "Interaction",
				kind = "enum",
				label = "Interaction",
				default = "auto",
				choices = { "auto", "prompt", "tool" },
				group = "Harvesting",
				help = "auto = tool if a tool is required, else a hold-E prompt.",
			},
			{
				attr = "DestroyOnDeplete",
				kind = "boolean",
				label = "Destroy when depleted",
				default = true,
				group = "Harvesting",
				help = "Off keeps the node so a reaction can turn it into a stump.",
			},
			{
				attr = "PromptText",
				kind = "string",
				label = "Prompt action text",
				default = "",
				placeholder = "Gather",
				group = "Prompt (hold-E only)",
			},
			{
				attr = "PromptObject",
				kind = "string",
				label = "Prompt object text",
				default = "",
				placeholder = "the resource / item id",
				group = "Prompt (hold-E only)",
			},
			{
				attr = "Yield",
				kind = "number",
				label = "Yield (legacy)",
				default = 0,
				min = 0,
				integer = true,
				advanced = true,
				group = "Harvesting",
				help = "Legacy single per-hit yield. Prefer Yield min / max.",
			},
		},
	},

	Mob = {
		name = "Mob",
		tag = "Mob",
		display = {
			title = "Mob (creature)",
			summary = "A creature with AI: wanders, chases, attacks or flees.",
			instance = "Model",
			order = 2,
			hint = "Needs a Model with a Humanoid and a PrimaryPart. Point it at a Mobs entry;"
				.. " every override below is optional.",
		},
		attributes = {
			{
				attr = "MobType",
				kind = "string",
				label = "Mob type",
				default = "",
				ref = "Mobs",
				placeholder = "a Mobs id (blank = the model's name)",
				group = "What it is",
				help = "The Content › Mobs entry to inherit from.",
			},
			{
				attr = "Faction",
				kind = "enum",
				label = "Faction",
				default = "",
				choices = { "", "hostile", "passive", "neutral" },
				group = "What it is",
				help = "Picks the AI profile. Blank = inherit the def (then neutral).",
			},
			{
				attr = "Health",
				kind = "number",
				label = "Health",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = "0 = inherit the mob def (or 50).",
			},
			{
				attr = "WalkSpeed",
				kind = "number",
				label = "Walk speed",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "RunSpeed",
				kind = "number",
				label = "Run speed",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "AggroRange",
				kind = "number",
				label = "Aggro range",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "LeashRange",
				kind = "number",
				label = "Leash range",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "AttackRange",
				kind = "number",
				label = "Attack range",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "AttackDamage",
				kind = "number",
				label = "Attack damage",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "AttackCooldown",
				kind = "number",
				label = "Attack cooldown (s)",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
			{
				attr = "WanderRadius",
				kind = "number",
				label = "Wander radius",
				default = 0,
				min = 0,
				group = "Overrides (0 = inherit)",
				help = INHERIT_ZERO,
			},
		},
	},

	QuestGiver = {
		name = "QuestGiver",
		tag = "QuestGiver",
		display = {
			title = "Quest giver",
			summary = "A sign or NPC that hands out one quest and takes its turn-in.",
			instance = "any",
			order = 3,
			hint = "Point it at a quest; the engine attaches the accept / turn-in prompt.",
		},
		attributes = {
			{
				attr = "Quest",
				kind = "string",
				label = "Quest",
				default = "",
				ref = "Quests",
				placeholder = "a Quests id",
				group = "What it is",
				help = "The quest this giver offers and accepts turn-ins for.",
			},
		},
	},
}

-- Chooser order. A reader must tolerate this naming an entry that no longer exists, AND entries
-- this list doesn't cover (a newer engine adding a component).
Schema.ORDER = { "Gatherable", "Mob", "QuestGiver" }

function Schema.get(name: string): ComponentSchema?
	return Schema.COMPONENTS[name]
end

-- Every schema, in ORDER first, then anything ORDER missed (alphabetically) — so a newer engine's
-- components still surface in an older reader.
function Schema.list(): { ComponentSchema }
	local out, seen = {}, {}
	for _, name in Schema.ORDER do
		local entry = Schema.COMPONENTS[name]
		if entry then
			seen[name] = true
			table.insert(out, entry)
		end
	end
	local rest = {}
	for name in Schema.COMPONENTS do
		if not seen[name] then
			table.insert(rest, name)
		end
	end
	table.sort(rest)
	for _, name in rest do
		table.insert(out, Schema.COMPONENTS[name])
	end
	return out
end

return Schema
