--!nonstrict
--[[
	Field — pure value plumbing shared by every schema-driven editor in the plugin (Engine Config
	and Build). No UI, no `plugin` global, no Instances: given a field spec ({ kind, min, max,
	integer, choices, check }) it coerces a raw input, formats a value for display, and decides
	whether a value equals its default.

	`kind` is one of "number" | "boolean" | "string" | "enum" | "color3" | "font". An UNKNOWN kind
	falls through to string, so a newer engine's schema can add kinds without breaking an older
	plugin.
]]

local Field = {}

local FLOAT_EPSILON = 1e-4

-- Coerce a raw input (usually a text box's string) to the field's type.
-- Returns { ok = true, value } | { ok = false, error }.
function Field.coerce(field: any, raw: any): any
	if field.kind == "number" then
		local n = if typeof(raw) == "number" then raw else tonumber(tostring(raw))
		if n == nil then
			return { ok = false, error = "expected a number" }
		end
		if n ~= n or n == math.huge or n == -math.huge then
			return { ok = false, error = "expected a finite number" }
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
	else -- "string", and any kind this plugin version doesn't know
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

-- A value as the creator should see it in a text box / button.
function Field.format(field: any, value: any): string
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

-- Deltas-only editors store a value ONLY when it differs from the default, so this decides whether
-- a write becomes a remove. Numbers compare with a RELATIVE epsilon: an absolute one would swallow
-- genuine overrides of very small values.
function Field.equalsDefault(field: any, value: any, default: any): boolean
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

return Field
