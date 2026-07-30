--!nonstrict
--[[
	BuildAdmin — headless logic for the Build page (issue #11): turn a selected Part or Model into
	a SurvivorCore world object (a Gatherable node, a Mob, a quest giver) by applying its tag and
	attributes, and edit those attributes afterwards.

	The SCHEMA comes from the ENGINE — readSchema() requires
	ReplicatedStorage.SurvivorCore.components.Schema live, so the plugin and the engine can never
	disagree about a component's fields. (That module is dependency-free precisely so the plugin can
	require it: the component modules themselves pull in server systems and must never be required
	in Edit mode.)

	Writes are DELTAS-ONLY, the same rule as the Stats and Engine Config editors:
	  • an attribute exists IFF its value differs from the component's default
	  • typing the default back (or blanking the box) REMOVES the attribute
	  • unset attributes keep following engine defaults across engine updates

	NOTE the two namespaces: this module writes PascalCase INSTANCE attributes (`ItemId`, `HP`) on
	world objects. The Content editor writes lowercase DEF fields (`item`, `hp`) on
	SurvivorCoreContent Configurations. A `ref` on a field links them (pick a def id) — they are
	never the same thing.

	No `plugin` global and no ChangeHistory here: the plugin main wraps every call in record().
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Field = require(script.Parent.Field)

local BuildAdmin = {}

local BOUND_ATTR = "_scBound" -- the engine's runtime bind marker

-- ── Schema (live from the engine) ────────────────────────────────────────────

local function findSchemaModule(): ModuleScript?
	local engine = ReplicatedStorage:FindFirstChild("SurvivorCore")
	local components = engine and engine:FindFirstChild("components")
	local module = components and components:FindFirstChild("Schema")
	if module and module:IsA("ModuleScript") then
		return module
	end
	return nil
end

-- { ok = true, source, components = {ComponentSchema}, byTag } | { ok = false, reason, components = {} }
-- Never errors. Re-read on every refresh so a re-synced engine self-heals.
function BuildAdmin.readSchema(): any
	local module = findSchemaModule()
	if not module then
		return {
			ok = false,
			components = {},
			reason = "SurvivorCore engine not found in this place (expected"
				.. " ReplicatedStorage.SurvivorCore.components.Schema — sync or insert the engine, then Refresh).",
		}
	end
	local ok, schema = pcall(require, module)
	if not ok or typeof(schema) ~= "table" or typeof(schema.COMPONENTS) ~= "table" then
		return {
			ok = false,
			components = {},
			reason = "Found the engine, but it declares no component schemas — Build needs"
				.. " SurvivorCore ≥ 0.9. Update the engine, then Refresh.",
		}
	end

	-- Build the ordered list defensively: ORDER may name an entry that no longer exists, and a
	-- NEWER engine may add entries ORDER doesn't cover. Include both, ORDER first.
	local list, seen = {}, {}
	for _, name in schema.ORDER or {} do
		local entry = schema.COMPONENTS[name]
		if typeof(entry) == "table" and typeof(entry.tag) == "string" then
			seen[name] = true
			table.insert(list, entry)
		end
	end
	local rest = {}
	for name, entry in schema.COMPONENTS do
		if not seen[name] and typeof(entry) == "table" and typeof(entry.tag) == "string" then
			table.insert(rest, name)
		end
	end
	table.sort(rest)
	for _, name in rest do
		table.insert(list, schema.COMPONENTS[name])
	end

	if #list == 0 then
		return { ok = false, components = {}, reason = "This engine declares no components." }
	end

	local byTag = {}
	for _, entry in list do
		byTag[entry.tag] = entry
	end
	return { ok = true, source = module:GetFullName(), components = list, byTag = byTag }
end

-- Attributes are only meaningful with a label/kind; tolerate a schema field we don't understand.
local function specsOf(schema: any): { any }
	return if typeof(schema) == "table" and typeof(schema.attributes) == "table" then schema.attributes else {}
end

function BuildAdmin.displayOf(schema: any): any
	local d = schema and schema.display
	if typeof(d) ~= "table" then
		return { title = (schema and schema.name) or "Component", summary = "" }
	end
	return d
end

-- ── Selection ────────────────────────────────────────────────────────────────

function BuildAdmin.classify(instance: Instance): string
	if instance:IsA("Model") then
		return "Model"
	elseif instance:IsA("BasePart") then
		return "BasePart"
	end
	return "other"
end

-- Can this component be applied to this instance? Returns (ok, reason).
function BuildAdmin.isEligible(instance: Instance, schema: any): (boolean, string?)
	local want: string = tostring(BuildAdmin.displayOf(schema).instance or "any")
	local got: string = BuildAdmin.classify(instance)
	if got == "other" then
		return false, "select a Part or a Model"
	end
	if want == "Model" then
		return got == "Model", "needs a Model (Humanoid + PrimaryPart)"
	elseif want == "BasePart" then
		return got == "BasePart", "needs a single Part"
	end
	return true, nil -- "any"
end

-- { instances, eligible, count } — `eligible` are Parts/Models (anything a component could go on).
function BuildAdmin.getSelection(): any
	local instances = Selection:Get()
	local eligible = {}
	for _, instance in instances do
		if BuildAdmin.classify(instance) ~= "other" then
			table.insert(eligible, instance)
		end
	end
	return { instances = instances, eligible = eligible, count = #instances }
end

-- What IS this instance already? { schema?, tag?, unknownTags, multi, stale }
--   multi  = it carries more than one component tag (v1 assumes one; say so rather than guess)
--   stale  = it carries the runtime bind marker in Edit mode (a copy-paste out of a Play session);
--            such an object silently never binds again, so every write path clears it.
function BuildAdmin.identify(instance: Instance, schemaRead: any): any
	local found, unknown = {}, {}
	for _, tag in CollectionService:GetTags(instance) do
		local entry = schemaRead.ok and schemaRead.byTag[tag]
		if entry then
			table.insert(found, entry)
		else
			table.insert(unknown, tag)
		end
	end
	return {
		schema = found[1],
		tag = found[1] and found[1].tag,
		unknownTags = unknown,
		multi = #found > 1,
		stale = instance:GetAttribute(BOUND_ATTR) ~= nil,
	}
end

-- ── Attribute read / write (deltas-only) ─────────────────────────────────────

-- { value, default, hasOverride, typeMismatch } — `typeMismatch` flags an attribute hand-set with
-- the wrong type (e.g. HP = "3"), which would error inside the component's onSetup at bind time.
function BuildAdmin.readField(instance: Instance, spec: any): any
	local raw = instance:GetAttribute(spec.attr)
	if raw == nil then
		return { value = spec.default, default = spec.default, hasOverride = false, typeMismatch = false }
	end
	local mismatch = spec.default ~= nil and typeof(raw) ~= typeof(spec.default)
	return { value = raw, default = spec.default, hasOverride = true, typeMismatch = mismatch }
end

local function alive(instance: Instance?): boolean
	return instance ~= nil and instance.Parent ~= nil
end

-- Set (or clear) one attribute. Blank input = reset. Writes ONLY when the value differs from the
-- component default. Returns { ok, action = "write"|"remove"|"noop", error? }.
function BuildAdmin.setField(instance: Instance, spec: any, raw: any): any
	if not alive(instance) then
		return { ok = false, action = "noop", error = "that object is gone" }
	end
	if typeof(raw) == "string" and string.match(raw, "^%s*$") then
		return BuildAdmin.resetField(instance, spec)
	end
	local coerced = Field.coerce(spec, raw)
	if not coerced.ok then
		return { ok = false, action = "noop", error = coerced.error }
	end
	if Field.equalsDefault(spec, coerced.value, spec.default) then
		return BuildAdmin.resetField(instance, spec)
	end
	instance:SetAttribute(spec.attr, coerced.value)
	instance:SetAttribute(BOUND_ATTR, nil) -- editing implies "bind me fresh next Play"
	return { ok = true, action = "write" }
end

function BuildAdmin.resetField(instance: Instance, spec: any): any
	if not alive(instance) then
		return { ok = false, action = "noop", error = "that object is gone" }
	end
	if instance:GetAttribute(spec.attr) ~= nil then
		instance:SetAttribute(spec.attr, nil)
		instance:SetAttribute(BOUND_ATTR, nil)
		return { ok = true, action = "remove" }
	end
	return { ok = true, action = "noop" }
end

-- Strip a component's declared attributes (and the engine's `_`-prefixed stamps) from an instance.
local function stripComponent(instance: Instance, schema: any)
	for _, spec in specsOf(schema) do
		instance:SetAttribute(spec.attr, nil)
	end
end

local function stripEngineStamps(instance: Instance)
	for name in instance:GetAttributes() do
		if string.sub(name, 1, 1) == "_" then
			instance:SetAttribute(name, nil)
		end
	end
end

-- Make each instance this component: add its tag, remove any OTHER component's tag and that
-- component's attributes, and clear engine stamps so it binds fresh on the next Play.
-- Deltas-only: no attributes are written, so the object follows every default until you change one.
-- Returns { applied, cleared, skipped }.
function BuildAdmin.applyType(instances: { Instance }, schema: any, all: { any }): any
	local applied, cleared, skipped = 0, 0, 0
	for _, instance in instances do
		local ok = alive(instance) and BuildAdmin.isEligible(instance, schema)
		if not ok then
			skipped += 1
			continue
		end
		for _, other in all do
			if other.tag ~= schema.tag and CollectionService:HasTag(instance, other.tag) then
				CollectionService:RemoveTag(instance, other.tag)
				stripComponent(instance, other)
				cleared += 1
			end
		end
		stripEngineStamps(instance)
		if not CollectionService:HasTag(instance, schema.tag) then
			CollectionService:AddTag(instance, schema.tag)
		end
		applied += 1
	end
	return { applied = applied, cleared = cleared, skipped = skipped }
end

-- The honest inverse of applyType: remove every known component tag, its attributes, and the
-- engine's `_`-prefixed stamps. Returns { cleared }.
function BuildAdmin.clear(instances: { Instance }, all: { any }): any
	local cleared = 0
	for _, instance in instances do
		if not alive(instance) then
			continue
		end
		local touched = false
		for _, schema in all do
			if CollectionService:HasTag(instance, schema.tag) then
				CollectionService:RemoveTag(instance, schema.tag)
				stripComponent(instance, schema)
				touched = true
			end
		end
		stripEngineStamps(instance)
		if touched then
			cleared += 1
		end
	end
	return { cleared = cleared }
end

-- How many instances in this place currently carry the component (drives the page footer).
function BuildAdmin.countInPlace(schema: any): number
	return #CollectionService:GetTagged(schema.tag)
end

return BuildAdmin
