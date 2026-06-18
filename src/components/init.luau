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
	instances and watch for new ones. A future builder UI can set these attributes
	visually instead of by hand.
]]

local CollectionService = game:GetService("CollectionService")

local Components = {}

export type Spec = {
	name: string,
	tag: string,
	attributes: { [string]: any }?, -- attribute name -> default value
	onSetup: ((instance: Instance, values: { [string]: any }) -> ())?,
}

local defined: { [string]: Spec } = {}

function Components.define(spec: Spec): Spec
	assert(spec.name and spec.tag, "Component requires `name` and `tag`")
	assert(defined[spec.name] == nil, `Component '{spec.name}' already defined`)
	defined[spec.name] = spec
	return spec
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
		spec.onSetup(instance, readAttributes(instance, spec.attributes))
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
