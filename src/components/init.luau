--[[
	Components — the creator-facing layer. A component binds engine behavior to a
	CollectionService tag, reading per-instance Attributes (with defaults). Creators
	tag their OWN objects and fill in attributes; no engine-side definition required.

		Components.define({
			name = "Gatherable",
			tag = "Gatherable",
			attributes = { ItemId = "unknown", Yield = 1, HP = 3 },
			onSetup = function(instance, values) ... end,
		})

	Call Components.scan() once (SurvivorCore.start does this) to bind existing tagged
	instances and watch for new ones.

	`attributes` accepts EITHER form:
	  • the shorthand map above (attribute -> default), or
	  • a SCHEMA array of AttributeSpec (kind/label/help/choices/…) — see components/Schema.luau.
	Both bind identically; the schema form additionally lets the Studio plugin render a setup form
	for the component, so a creator picks "what is this object?" instead of typing attribute names.
	Declare a `display` too ({ title, summary, instance }) so it can appear in that chooser.
]]

local CollectionService = game:GetService("CollectionService")

local Schema = require(script.Schema)

local Components = {}

export type AttributeSpec = Schema.AttributeSpec

export type Spec = {
	name: string,
	tag: string,
	-- attribute -> default (shorthand) OR an array of AttributeSpec (schema form)
	attributes: ({ [string]: any } | { Schema.AttributeSpec })?,
	display: Schema.Display?, -- builder-UI presentation (title / summary / eligible class / hint)
	onSetup: ((instance: Instance, values: { [string]: any }) -> ())?,
}

local defined: { [string]: Spec } = {}
local schemas: { [string]: Schema.ComponentSchema } = {}
local defaults: { [string]: { [string]: any } } = {} -- the attr->default map bind() reads

function Components.define(spec: Spec): Spec
	assert(spec.name and spec.tag, "Component requires `name` and `tag`")
	assert(defined[spec.name] == nil, `Component '{spec.name}' already defined`)
	local attributes = Schema.normalize(spec.attributes)
	defined[spec.name] = spec
	schemas[spec.name] = {
		name = spec.name,
		tag = spec.tag,
		display = spec.display or { title = spec.name, summary = "" },
		attributes = attributes,
	}
	defaults[spec.name] = Schema.defaults(attributes)
	return spec
end

-- Introspection (the runtime mirror of components/Schema.luau, including anything a game defined
-- at runtime — which the edit-time plugin can't see).
function Components.getSchema(name: string): Schema.ComponentSchema?
	return schemas[name]
end

function Components.listSchemas(): { Schema.ComponentSchema }
	local out = {}
	for _, entry in schemas do
		table.insert(out, entry)
	end
	table.sort(out, function(a, b)
		local ao = (a.display and tonumber(a.display.order)) or 100
		local bo = (b.display and tonumber(b.display.order)) or 100
		if ao ~= bo then
			return ao < bo
		end
		return a.name < b.name
	end)
	return out
end

local function readAttributes(instance: Instance, attributes: { [string]: any }?)
	local values = {}
	if attributes then
		for attrName, default in attributes do
			local v = instance:GetAttribute(attrName)
			values[attrName] = if v == nil then default else v
		end
	end
	return values
end

local function bind(instance: Instance, spec: Spec)
	if instance:GetAttribute("_scBound") then
		return
	end
	instance:SetAttribute("_scBound", true)
	if spec.onSetup then
		-- Always the normalized attr->default map, so both `attributes` forms bind identically.
		spec.onSetup(instance, readAttributes(instance, defaults[spec.name]))
	end
end

-- Bind everything currently tagged, then keep binding new instances as they appear.
function Components.scan()
	for _, spec in defined do
		for _, instance in CollectionService:GetTagged(spec.tag) do
			task.spawn(bind, instance, spec)
		end
		CollectionService:GetInstanceAddedSignal(spec.tag):Connect(function(instance)
			bind(instance, spec)
		end)
	end
end

return Components
