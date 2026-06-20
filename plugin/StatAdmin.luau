--!nonstrict
--[[
	StatAdmin — the pure, requirable LOGIC layer of the Stat Admin plugin. NO Studio
	widget, NO `plugin` global, NO ChangeHistoryService: every public function can be
	required and exercised headlessly (e.g. via execute_luau) without opening the dock.
	The UI (StatAdminUi) and the plugin main (init.server) are thin layers over this.

	THE CRITICAL CORRECTNESS PROPERTY — a deltas-only, LOCKED model.
	The engine resolves a stat field as: engine defaults -> Config.override -> the
	`SurvivalStatsConfig` instance (HIGHEST priority). That instance is OWNER data the
	engine only ever install-if-absent seeds; it never overwrites it. So:
	  * We WRITE an attribute ONLY when the owner's value differs from the engine default.
	  * We REMOVE the attribute (Reset, or editing back to the default) so the field falls
	    back to the (improvable) engine default — never a frozen copy of today's default.
	Unset fields therefore keep following engine defaults across updates; explicit
	overrides survive forever. Nothing tuned is lost; nothing left alone is frozen.

	HARD GUARDRAIL — we write ONLY the seven owner-tunable attributes (exactly the engine's
	STUDIO_ATTR_MAP): RatePerSecond, Max, Start, WarnAt, Display, Icon, ValueFormat.
	We NEVER read-as-editable or WRITE `Invert` or `DangerHigh`: those are engine-owned stat
	SEMANTICS the engine deliberately ignores on the instance. Writing them would re-freeze
	the just-fixed Hunger/Thirst/Poison fill-direction bug. There is literally no code path
	here that can SetAttribute either name (see the TUNABLE allow-list + the assert in write()).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatAdmin = {}

StatAdmin.INSTANCE_NAME = "SurvivalStatsConfig"

-- Floats from the engine (e.g. perMinutes(30) = 0.0555…) are stored rounded in the model
-- JSON (0.055556). Treat values within this epsilon as "equal to default" so typing the
-- displayed default back in REMOVES the override rather than freezing a near-duplicate.
local FLOAT_EPSILON = 1e-4

export type Kind = "number" | "boolean" | "string" | "enum"

export type FieldSpec = {
	attr: string, -- attribute name on the per-stat Configuration child (and the engine map key)
	field: string, -- the resolved field name on StatDefs.DEFAULTS records
	kind: Kind,
	label: string, -- friendly label for the UI
	choices: { string }?, -- for kind == "enum"
}

-- THE allow-list. The ONLY attributes the plugin ever reads-as-editable or writes. Order
-- is the UI render order; RatePerSecond is first (the headline knob). Note the deliberate
-- ABSENCE of Invert and DangerHigh — they are engine-owned semantics, never tunable here.
StatAdmin.TUNABLE = {
	{ attr = "RatePerSecond", field = "ratePerSecond", kind = "number", label = "Rate / second" },
	{ attr = "Max", field = "max", kind = "number", label = "Max" },
	{ attr = "Start", field = "start", kind = "number", label = "Start" },
	{ attr = "WarnAt", field = "warnAt", kind = "number", label = "Warn at %" },
	{ attr = "Display", field = "display", kind = "boolean", label = "Display" },
	{ attr = "Icon", field = "icon", kind = "string", label = "Icon" },
	{
		attr = "ValueFormat",
		field = "valueFormat",
		kind = "enum",
		label = "Value format",
		choices = { "fraction", "percent", "value", "none" },
	},
} :: { FieldSpec }

-- attr -> FieldSpec, for O(1) lookup + the write-time allow-list check.
local SPEC_BY_ATTR: { [string]: FieldSpec } = {}
for _, spec in StatAdmin.TUNABLE do
	SPEC_BY_ATTR[spec.attr] = spec
end

StatAdmin.VALUE_FORMATS = { "fraction", "percent", "value", "none" }

export type StatEntry = {
	name: string,
	-- Engine default for each of the seven tunable attributes (keyed by ATTRIBUTE name, so the
	-- UI, the diff and the write path all speak the same vocabulary as STUDIO_ATTR_MAP).
	defaults: { [string]: any },
}

export type Roster = {
	ok: boolean,
	source: string?, -- human-readable data source, e.g. "ReplicatedStorage.SurvivorCore"
	reason: string?, -- when ok == false, why (for the empty state)
	stats: { StatEntry },
}

-- ---------------------------------------------------------------------------
-- Roster: the LIVE engine roster + defaults, read at call time (never baked).
-- ---------------------------------------------------------------------------

-- Normalize one StatDefs.DEFAULTS record into the seven tunable attributes, supplying the
-- two the array omits (icon "" and valueFormat "fraction" — matching StatDefs.install()).
-- dangerHigh / invert are intentionally NOT read here: they are not tunable.
local function toDefaults(def: any): { [string]: any }
	return {
		RatePerSecond = def.ratePerSecond,
		Max = def.max,
		Start = def.start,
		WarnAt = def.warnAt,
		Display = def.display,
		Icon = def.icon or "",
		ValueFormat = def.valueFormat or "fraction",
	}
end

-- Reads the live engine roster from ReplicatedStorage.SurvivorCore.stats.StatDefs.DEFAULTS.
-- DEFAULTS is the shipped roster AS AUTHORED (pre-merge), a plain array safe to require
-- read-only — so the plugin's notion of "engine default" provably matches what the engine
-- resolves absent the instance. Returns { ok = false, … } (never errors) when the engine
-- isn't in the place, so the UI can render an instructional empty state and write nothing.
function StatAdmin.readRoster(): Roster
	local sc = ReplicatedStorage:FindFirstChild("SurvivorCore")
	if not sc then
		return {
			ok = false,
			reason = "SurvivorCore engine not found in ReplicatedStorage. Sync the engine "
				.. "(rojo serve) or insert SurvivorCore.rbxm, then press Refresh.",
			stats = {},
		}
	end

	local statsFolder = sc:FindFirstChild("stats")
	local statDefsModule = statsFolder and statsFolder:FindFirstChild("StatDefs")
	if not statDefsModule or not statDefsModule:IsA("ModuleScript") then
		return {
			ok = false,
			reason = "Found SurvivorCore but not stats.StatDefs — is the engine fully synced?",
			stats = {},
		}
	end

	local ok, defsOrErr = pcall(require, statDefsModule)
	if not ok or typeof(defsOrErr) ~= "table" or typeof(defsOrErr.DEFAULTS) ~= "table" then
		return {
			ok = false,
			reason = "Could not read StatDefs.DEFAULTS from the engine.",
			stats = {},
		}
	end

	local stats: { StatEntry } = {}
	for _, def in defsOrErr.DEFAULTS do
		table.insert(stats, { name = def.name, defaults = toDefaults(def) })
	end

	return {
		ok = true,
		source = "ReplicatedStorage.SurvivorCore",
		stats = stats,
	}
end

-- ---------------------------------------------------------------------------
-- Instance / child resolution. INSTALL-IF-ABSENT, never clobbering.
-- ---------------------------------------------------------------------------

-- The live SurvivalStatsConfig instance, or nil. Read-only — never creates.
function StatAdmin.getInstance(): Instance?
	return ReplicatedStorage:FindFirstChild(StatAdmin.INSTANCE_NAME)
end

-- The per-stat child Configuration, or nil. Read-only — never creates.
function StatAdmin.getNode(statName: string): Instance?
	local instance = StatAdmin.getInstance()
	return instance and instance:FindFirstChild(statName) or nil
end

-- Find-or-create the SurvivalStatsConfig Configuration. Creates ONLY when missing; never
-- touches an existing one. Called lazily, only from the write path (a real override).
function StatAdmin.ensureInstance(): Instance
	local instance = StatAdmin.getInstance()
	if not instance then
		instance = Instance.new("Configuration")
		instance.Name = StatAdmin.INSTANCE_NAME
		instance.Parent = ReplicatedStorage
	end
	return instance
end

-- Find-or-create the per-stat child Configuration. A freshly created node carries ZERO
-- attributes, so every field still follows the engine default until one is explicitly set.
function StatAdmin.ensureNode(statName: string): Instance
	local instance = StatAdmin.ensureInstance()
	local node = instance:FindFirstChild(statName)
	if not node then
		node = Instance.new("Configuration")
		node.Name = statName
		node.Parent = instance
	end
	return node
end

-- ---------------------------------------------------------------------------
-- Effective values: instance override (if present) else engine default.
-- ---------------------------------------------------------------------------

export type Effective = {
	value: any, -- the value the engine would resolve: override if present, else default
	default: any, -- the engine default
	hasOverride: boolean, -- true iff the attribute exists on the per-stat child
}

-- Resolves one field's effective value + whether it is currently overridden on the instance.
-- `default` is the engine default for that (stat, attr), as read from the roster.
function StatAdmin.readEffective(statName: string, attr: string, default: any): Effective
	assert(SPEC_BY_ATTR[attr], `StatAdmin: '{attr}' is not an owner-tunable attribute`)
	local node = StatAdmin.getNode(statName)
	local override = node and node:GetAttribute(attr) or nil
	if override ~= nil then
		return { value = override, default = default, hasOverride = true }
	end
	return { value = default, default = default, hasOverride = false }
end

-- ---------------------------------------------------------------------------
-- Coercion + default-equality (the diff that drives write-vs-remove).
-- ---------------------------------------------------------------------------

-- Coerce/validate a raw UI value for a given attr. Returns (ok, coercedValue, errMessage).
-- Numbers parse via tonumber; WarnAt clamps to 0-100; ValueFormat is constrained to the
-- four legal strings; Display -> boolean; Icon -> string ("" allowed).
function StatAdmin.coerce(attr: string, raw: any): (boolean, any, string?)
	local spec = SPEC_BY_ATTR[attr]
	if not spec then
		return false, nil, `'{attr}' is not tunable`
	end

	if spec.kind == "number" then
		local n = tonumber(raw)
		if n == nil then
			return false, nil, "not a number"
		end
		if attr == "WarnAt" then
			n = math.clamp(n, 0, 100)
		end
		return true, n, nil
	elseif spec.kind == "boolean" then
		if typeof(raw) == "boolean" then
			return true, raw, nil
		end
		if raw == "true" then
			return true, true, nil
		elseif raw == "false" then
			return true, false, nil
		end
		return false, nil, "not a boolean"
	elseif spec.kind == "enum" then
		local s = tostring(raw)
		if not table.find(spec.choices :: { string }, s) then
			return false, nil, "not a valid value format"
		end
		return true, s, nil
	else -- string (Icon)
		return true, tostring(raw), nil
	end
end

-- True when `value` is (effectively) the engine default — numbers within FLOAT_EPSILON,
-- booleans/strings compared exactly. Used to collapse a no-op edit into an attribute removal.
function StatAdmin.equalsDefault(attr: string, value: any, default: any): boolean
	local spec = SPEC_BY_ATTR[attr]
	if spec and spec.kind == "number" then
		local v, d = tonumber(value), tonumber(default)
		if v == nil or d == nil then
			return false
		end
		return math.abs(v - d) <= FLOAT_EPSILON
	end
	return value == default
end

-- ---------------------------------------------------------------------------
-- The single write decision point + reset.
-- ---------------------------------------------------------------------------

-- Low-level guarded SetAttribute. The assert makes it IMPOSSIBLE to write a non-tunable
-- attribute (Invert / DangerHigh / anything else) — the engine-owned semantics are safe.
local function write(node: Instance, attr: string, value: any?)
	assert(SPEC_BY_ATTR[attr], `StatAdmin: refusing to write non-tunable attribute '{attr}'`)
	node:SetAttribute(attr, value)
end

export type SetResult = {
	ok: boolean,
	action: "write" | "remove" | "noop",
	error: string?,
}

-- THE deltas-only write rule. Coerce + validate, then:
--   * value EQUALS the engine default  -> REMOVE the attribute (falls back to the default).
--   * value DIFFERS from the default    -> WRITE it (create instance/child on demand).
-- We only ever touch the ONE attribute passed; sibling attributes / other stats / unknown
-- owner data are never read-modify-rewritten, so nothing the owner set elsewhere is clobbered.
function StatAdmin.setOverride(statName: string, attr: string, raw: any, default: any): SetResult
	if not SPEC_BY_ATTR[attr] then
		return { ok = false, action = "noop", error = `'{attr}' is not an owner-tunable attribute` }
	end

	local okCoerce, value, err = StatAdmin.coerce(attr, raw)
	if not okCoerce then
		return { ok = false, action = "noop", error = err }
	end

	if StatAdmin.equalsDefault(attr, value, default) then
		-- No real delta: ensure the attribute is absent (typed-back-to-default == reset).
		local node = StatAdmin.getNode(statName)
		if node and node:GetAttribute(attr) ~= nil then
			write(node, attr, nil)
			return { ok = true, action = "remove" }
		end
		return { ok = true, action = "noop" }
	end

	-- Genuine override: create instance/child only now, write only this attribute.
	local node = StatAdmin.ensureNode(statName)
	write(node, attr, value)
	return { ok = true, action = "write" }
end

-- Reset a single field: remove its attribute so it follows the engine default. No-op if
-- the child / attribute doesn't exist. Never creates anything.
function StatAdmin.resetOverride(statName: string, attr: string): SetResult
	if not SPEC_BY_ATTR[attr] then
		return { ok = false, action = "noop", error = `'{attr}' is not an owner-tunable attribute` }
	end
	local node = StatAdmin.getNode(statName)
	if node and node:GetAttribute(attr) ~= nil then
		write(node, attr, nil)
		return { ok = true, action = "remove" }
	end
	return { ok = true, action = "noop" }
end

-- Reset every tunable field on one stat (removes all seven attributes if present).
function StatAdmin.resetStat(statName: string)
	for _, spec in StatAdmin.TUNABLE do
		StatAdmin.resetOverride(statName, spec.attr)
	end
end

-- Reset every tunable field on every stat in the live roster.
function StatAdmin.resetAll()
	local roster = StatAdmin.readRoster()
	for _, entry in roster.stats do
		StatAdmin.resetStat(entry.name)
	end
end

return StatAdmin
