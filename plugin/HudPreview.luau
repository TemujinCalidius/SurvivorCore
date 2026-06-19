--!nonstrict
--[[
	HudPreview — a REVERSIBLE, edit-mode "what it looks like in play" preview for the HUD.

	Roblox doesn't run the HUD's client binder in Studio's Edit view, so an authored
	`SurvivalHud` shows its static template: full bars, blank value text, and only the
	shipped DEFAULT icons (an admin/config icon override isn't visible until you Play).
	This paints, in Edit, what the runtime binder WOULD render — resolved icons (incl.
	owner overrides) + a sample partial fill + a sample value readout — so the owner can
	tune the HUD and see the real thing without pressing Play.

	It mirrors the engine binder's resolution (`src/client/Hud.luau`) so the preview matches
	runtime: per-bar `Icon` attribute > the stat's effective `icon` (config/admin override, else
	the shipped default) for icons; `FillAxis`-aware fill sizing; the per-stat `ValueFormat` for
	the readout. (It does NOT consult the `Assets` registry tier — that's populated at runtime, so
	it's empty in Edit anyway.) Stat *fill direction* is engine-owned, so the sample is a plain
	ratio; we don't guess invert/dangerHigh.

	REVERSIBLE: every property it changes is snapshotted (once) before the first write, and
	`clear()` restores the snapshots exactly. Each apply/clear is wrapped by the plugin main in a
	single ChangeHistory recording, so Studio undo reverts it too.
]]

local StarterGui = game:GetService("StarterGui")

local HudPreview = {}

local HUD_NAME = "SurvivalHud"
local SAMPLE_COUNTER = 1250 -- a believable credits value for the readout

-- inst -> { [prop] = originalValue }. The live preview's snapshot of everything we touched.
local snapshots: { [Instance]: { [string]: any } } = {}

-- Snapshot inst[prop] ONCE (so re-applying preview never captures a previewed value as original).
local function remember(inst: Instance, prop: string)
	local bag = snapshots[inst]
	if not bag then
		bag = {}
		snapshots[inst] = bag
	end
	if bag[prop] == nil then
		bag[prop] = (inst :: any)[prop]
	end
end

-- A deterministic, varied sample fill ratio per stat (so bars don't all look identical, and the
-- preview is stable across clicks). Range ~0.40–0.85.
local function sampleRatio(name: string): number
	local sum = 0
	for i = 1, #name do
		sum += string.byte(name, i)
	end
	return 0.4 + (sum % 46) / 100
end

-- Mirror of Hud.luau formatValue for the sample readout.
local function formatValue(format: string, value: number, max: number): string
	if format == "none" then
		return ""
	elseif format == "percent" then
		local pct = if max > 0 then math.floor((value / max) * 100 + 0.5) else 0
		return string.format("%d%%", math.clamp(pct, 0, 100))
	elseif format == "value" then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%d/%d", math.floor(value + 0.5), math.floor(max + 0.5)) -- fraction
end

-- Mirror of Hud.luau formatCounter ("1,250").
local function formatCounter(n: number): string
	local digits = tostring(math.abs(math.floor(n + 0.5)))
	local grouped = ""
	while #digits > 3 do
		grouped = "," .. string.sub(digits, -3) .. grouped
		digits = string.sub(digits, 1, -4)
	end
	return digits .. grouped
end

-- The authored HUD in StarterGui, or nil. Read-only.
function HudPreview.findHud(): Instance?
	return StarterGui:FindFirstChild(HUD_NAME)
end

local function isImage(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("ImageLabel") or inst:IsA("ImageButton"))
end

export type Result = { ok: boolean, count: number, reason: string? }

-- Paint the preview onto the HUD (StarterGui's by default; `hudRoot` lets callers/tests target a
-- specific tree). `StatAdmin` supplies the effective (config-aware) icon / max / value-format per
-- stat. Returns how many bars/counters were painted.
function HudPreview.apply(StatAdmin: any, hudRoot: Instance?): Result
	local hud = hudRoot or HudPreview.findHud()
	if not hud then
		return {
			ok = false,
			count = 0,
			reason = "No SurvivalHud in StarterGui — sync the engine/HUD, then preview.",
		}
	end

	-- Effective per-stat values (config/admin override else the shipped default), keyed by stat.
	local roster = StatAdmin.readRoster()
	local defaultsByName: { [string]: any } = {}
	if roster.ok then
		for _, entry in roster.stats do
			defaultsByName[entry.name] = entry.defaults
		end
	end
	local function effective(stat: string, attr: string): any
		local defs = defaultsByName[stat]
		return StatAdmin.readEffective(stat, attr, defs and defs[attr]).value
	end

	local count = 0
	for _, node in hud:GetDescendants() do
		local stat = node:GetAttribute("Stat")
		local counter = node:GetAttribute("Counter")
		local key = stat or counter
		if typeof(key) ~= "string" then
			continue
		end

		-- Icon: per-bar attribute wins, else the stat's effective icon (counters have no roster
		-- entry, so they rely on the per-bar attribute the template bakes).
		local perBar = node:GetAttribute("Icon")
		local icon: string = ""
		if typeof(perBar) == "string" and perBar ~= "" then
			icon = perBar
		elseif typeof(stat) == "string" and defaultsByName[stat] then
			local resolved = effective(stat, "Icon")
			icon = if typeof(resolved) == "string" then resolved else ""
		end

		local iconLabel = node:FindFirstChild("Icon")
		if isImage(iconLabel) then
			remember(iconLabel :: Instance, "Image")
			remember(iconLabel :: Instance, "Visible");
			(iconLabel :: any).Image = icon;
			(iconLabel :: any).Visible = icon ~= ""
		end

		if typeof(stat) == "string" then
			local max = tonumber(effective(stat, "Max")) or 100
			local ratio = sampleRatio(stat)
			local sampleValue = ratio * max

			local fill = node:FindFirstChild("Fill")
			if fill and fill:IsA("GuiObject") then
				remember(fill, "Size")
				local size = (fill :: GuiObject).Size
				local axis = node:GetAttribute("FillAxis")
				if axis == "Y" then
					(fill :: GuiObject).Size = UDim2.new(size.X.Scale, size.X.Offset, ratio, 0)
				else
					(fill :: GuiObject).Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset)
				end
			end

			local valueLabel = node:FindFirstChild("Value")
			if valueLabel and valueLabel:IsA("TextLabel") then
				local format = effective(stat, "ValueFormat")
				format = if typeof(format) == "string" then format else "fraction"
				remember(valueLabel, "Text");
				(valueLabel :: TextLabel).Text = formatValue(format, sampleValue, max)
			end
		elseif typeof(counter) == "string" then
			local valueLabel = node:FindFirstChild("Value")
			if valueLabel and valueLabel:IsA("TextLabel") then
				remember(valueLabel, "Text");
				(valueLabel :: TextLabel).Text = formatCounter(SAMPLE_COUNTER)
			end
		end

		count += 1
	end

	return { ok = true, count = count }
end

-- Restore every property the preview changed, then forget them. Safe to call with nothing active
-- (returns count = 0). Stale/destroyed instances are skipped.
function HudPreview.clear(): Result
	local count = 0
	for inst, bag in snapshots do
		if inst and inst.Parent then
			for prop, value in bag do
				pcall(function()
					(inst :: any)[prop] = value
				end)
			end
			count += 1
		end
	end
	snapshots = {}
	return { ok = true, count = count }
end

-- True when a preview is currently applied (used by the UI to label the toggle).
function HudPreview.isActive(): boolean
	return next(snapshots) ~= nil
end

return HudPreview
