--!nonstrict
--[[
	ConfigAdmin — headless logic for the Engine Config editor (issue #21). The generic sibling of
	StatAdmin: it edits the persisted `ReplicatedStorage.SurvivorCoreEngineConfig` instance the
	engine layers over every Config section at start()/startClient().

	The SCHEMA (sections → groups → typed fields) comes from the ENGINE — readSchema() requires
	ReplicatedStorage.SurvivorCore.shared.EngineConfig live, so plugin and engine can never
	disagree about fields, kinds or defaults. Writes are DELTAS-ONLY, same rule as StatAdmin:

	  • an attribute exists IFF the owner's value differs from the engine default
	  • typing the default back (or blanking the box) REMOVES the attribute
	  • unset fields keep following engine defaults across engine updates

	Instance shape: <instance>/<Section>/(attributes | <Group>/attributes). Field kinds:
	number | boolean | string | enum | color3 (native Color3 attribute) | font (attribute is an
	Enum.Font NAME string; the engine resolves it at apply time).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigAdmin = {}

ConfigAdmin.INSTANCE_NAME = "SurvivorCoreEngineConfig"

-- Relative float tolerance: |v−d| ≤ EPS·max(|v|,|d|,1e-6). StatAdmin's absolute 1e-4 would
-- swallow genuine overrides of tiny rates (Consequences drains ≈ 0.0035/s); the relative form
-- still collapses display round-trip noise.
local FLOAT_EPSILON = 1e-4

-- ── Schema (live from the engine) ────────────────────────────────────────────

local function findEngineConfigModule(): ModuleScript?
	local engine = ReplicatedStorage:FindFirstChild("SurvivorCore")
	local shared = engine and engine:FindFirstChild("shared")
	local module = shared and shared:FindFirstChild("EngineConfig")
	if module and module:IsA("ModuleScript") then
		return module
	end
	return nil
end

-- Read the schema + per-section defaults from the live engine. Never errors:
-- { ok = true, source, sections, defaults } | { ok = false, reason, sections = {} }
function ConfigAdmin.readSchema(): any
	local module = findEngineConfigModule()
	if not module then
		return {
			ok = false,
			reason = "SurvivorCore engine not found in this place (expected"
				.. " ReplicatedStorage.SurvivorCore.shared.EngineConfig — sync/insert the engine, then Refresh).",
			sections = {},
		}
	end
	local ok, engineConfig = pcall(require, module)
	if not ok or typeof(engineConfig) ~= "table" or typeof(engineConfig.SECTIONS) ~= "table" then
		return {
			ok = false,
			reason = "Found the engine, but its EngineConfig module failed to load — is the engine"
				.. " up to date? (Engine Config needs SurvivorCore ≥ 0.8.)",
			sections = {},
		}
	end
	local defaults: { [string]: any } = {}
	for _, section in engineConfig.SECTIONS do
		defaults[section.id] = engineConfig.getDefaults(section.id)
	end
	return {
		ok = true,
		source = module:GetFullName(),
		sections = engineConfig.SECTIONS,
		defaults = defaults,
	}
end

-- ── Instance access (read-only vs ensure) ────────────────────────────────────

function ConfigAdmin.getNode(sectionId: string, groupName: string?): Instance?
	local instance = ReplicatedStorage:FindFirstChild(ConfigAdmin.INSTANCE_NAME)
	local section = instance and instance:FindFirstChild(sectionId)
	if groupName then
		return section and section:FindFirstChild(groupName)
	end
	return section
end

local function ensureConfiguration(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local node = Instance.new("Configuration")
	node.Name = name
	node.Parent = parent
	return node
end

function ConfigAdmin.ensureNode(sectionId: string, groupName: string?): Instance
	local instance = ReplicatedStorage:FindFirstChild(ConfigAdmin.INSTANCE_NAME)
	if not instance then
		instance = Instance.new("Configuration")
		instance.Name = ConfigAdmin.INSTANCE_NAME
		instance.Parent = ReplicatedStorage
	end
	local section = ensureConfiguration(instance, sectionId)
	if groupName then
		return ensureConfiguration(section, groupName)
	end
	return section
end

-- ── Effective values ─────────────────────────────────────────────────────────

-- The value the engine will use for a field: the instance override when present, else `default`.
function ConfigAdmin.readEffective(sectionId: string, groupName: string?, attr: string, default: any): any
	local node = ConfigAdmin.getNode(sectionId, groupName)
	local override = node and node:GetAttribute(attr)
	if override ~= nil then
		return { value = override, default = default, hasOverride = true }
	end
	return { value = default, default = default, hasOverride = false }
end

-- ── Coercion & default equality ──────────────────────────────────────────────

-- Parse a raw edit (usually TextBox text) per the field spec. Returns { ok, value } or
-- { ok = false, error }. A blank string is handled by setOverride (it means "reset").
function ConfigAdmin.coerce(field: any, raw: any): any
	if field.kind == "number" then
		local n = if typeof(raw) == "number" then raw else tonumber(tostring(raw))
		if n == nil then
			return { ok = false, error = "expected a number" }
		end
		if field.min then
			n = math.max(n, field.min)
		end
		if field.max then
			n = math.min(n, field.max)
		end
		if field.integer then
			n = math.floor(n + 0.5)
		end
		return { ok = true, value = n }
	elseif field.kind == "boolean" then
		if typeof(raw) == "boolean" then
			return { ok = true, value = raw }
		end
		local s = string.lower(tostring(raw))
		if s == "true" then
			return { ok = true, value = true }
		elseif s == "false" then
			return { ok = true, value = false }
		end
		return { ok = false, error = "expected true or false" }
	elseif field.kind == "enum" then
		local s = tostring(raw)
		for _, choice in field.choices or {} :: { string } do
			if choice == s then
				return { ok = true, value = s }
			end
		end
		return { ok = false, error = `must be one of: {table.concat(field.choices or {}, ", ")}` }
	elseif field.kind == "color3" then
		if typeof(raw) == "Color3" then
			return { ok = true, value = raw }
		end
		local r, g, b = string.match(tostring(raw), "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
		if not r then
			return { ok = false, error = "expected R, G, B (0-255 each)" }
		end
		local rn, gn, bn = tonumber(r), tonumber(g), tonumber(b)
		if rn > 255 or gn > 255 or bn > 255 then
			return { ok = false, error = "channels are 0-255" }
		end
		return { ok = true, value = Color3.fromRGB(rn, gn, bn) }
	elseif field.kind == "font" then
		local s = tostring(raw)
		local ok, font = pcall(function()
			return (Enum.Font :: any)[s]
		end)
		if not ok or typeof(font) ~= "EnumItem" then
			return { ok = false, error = `'{s}' is not an Enum.Font name` }
		end
		return { ok = true, value = s } -- stored as the NAME string; the engine resolves it
	else -- "string" (incl. check = keycode/assetId)
		local s = tostring(raw)
		if field.check == "keycode" then
			local ok, keyCode = pcall(function()
				return (Enum.KeyCode :: any)[s]
			end)
			if not ok or typeof(keyCode) ~= "EnumItem" then
				return { ok = false, error = `'{s}' is not an Enum.KeyCode name` }
			end
		end
		return { ok = true, value = s }
	end
end

-- Does a coerced value equal the engine default (→ store nothing)? Kind-aware: fonts compare
-- the stored NAME against the default Enum.Font; Color3 compares exactly (both sides come from
-- fromRGB construction); numbers use the relative epsilon.
function ConfigAdmin.equalsDefault(field: any, value: any, default: any): boolean
	if field.kind == "number" then
		if typeof(value) ~= "number" or typeof(default) ~= "number" then
			return value == default
		end
		local scale = math.max(math.abs(value), math.abs(default), 1e-6)
		return math.abs(value - default) <= FLOAT_EPSILON * scale
	elseif field.kind == "font" then
		local defaultName = if typeof(default) == "EnumItem" then default.Name else tostring(default)
		return value == defaultName
	end
	return value == default
end

-- Display formatting for effective values/defaults (what the TextBox shows).
function ConfigAdmin.formatValue(field: any, value: any): string
	if value == nil then
		return ""
	end
	if field.kind == "color3" and typeof(value) == "Color3" then
		return string.format(
			"%d, %d, %d",
			math.round(value.R * 255),
			math.round(value.G * 255),
			math.round(value.B * 255)
		)
	end
	if field.kind == "font" and typeof(value) == "EnumItem" then
		return value.Name
	end
	return tostring(value)
end

-- ── Writes (the deltas-only decision point) ──────────────────────────────────

-- Set (or clear) one field. Blank input = reset to default. Writes ONLY when the value differs
-- from the engine default; removes the attribute when it matches.
-- Returns { ok, action = "write"|"remove"|"noop", error? }.
function ConfigAdmin.setOverride(sectionId: string, groupName: string?, field: any, raw: any, default: any): any
	if typeof(raw) == "string" and string.match(raw, "^%s*$") then
		return ConfigAdmin.resetOverride(sectionId, groupName, field.attr)
	end
	local coerced = ConfigAdmin.coerce(field, raw)
	if not coerced.ok then
		return { ok = false, action = "noop", error = coerced.error }
	end
	if ConfigAdmin.equalsDefault(field, coerced.value, default) then
		return ConfigAdmin.resetOverride(sectionId, groupName, field.attr)
	end
	local node = ConfigAdmin.ensureNode(sectionId, groupName)
	node:SetAttribute(field.attr, coerced.value)
	return { ok = true, action = "write" }
end

function ConfigAdmin.resetOverride(sectionId: string, groupName: string?, attr: string): any
	local node = ConfigAdmin.getNode(sectionId, groupName)
	if node and node:GetAttribute(attr) ~= nil then
		node:SetAttribute(attr, nil)
		return { ok = true, action = "remove" }
	end
	return { ok = true, action = "noop" }
end

-- Remove every override in one section (all groups). Returns the number removed.
function ConfigAdmin.resetSection(section: any): number
	local removed = 0
	for _, group in section.groups do
		local node = ConfigAdmin.getNode(section.id, group.name)
		if node then
			for _, field in group.fields do
				if node:GetAttribute(field.attr) ~= nil then
					node:SetAttribute(field.attr, nil)
					removed += 1
				end
			end
		end
	end
	return removed
end

-- Count the overrides currently set in one section (drives the "n overridden" footer).
function ConfigAdmin.countOverrides(section: any): number
	local count = 0
	for _, group in section.groups do
		local node = ConfigAdmin.getNode(section.id, group.name)
		if node then
			for _, field in group.fields do
				if node:GetAttribute(field.attr) ~= nil then
					count += 1
				end
			end
		end
	end
	return count
end

return ConfigAdmin
