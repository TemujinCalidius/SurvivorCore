--[[
	Hud — the client HUD binder. CLIENT-ONLY.

	Drives any `SurvivorStatBar`-tagged GUI from the player's stat Attributes (which
	the server writes and Roblox auto-replicates — no RemoteEvents). The owner authors
	and re-textures the actual ScreenGui in StarterGui; this only ever sets each bar's
	`Fill` size + color, so restyling needs zero code.

	Per-bar contract (attributes on the tagged Frame; most default from the stat config,
	so owners usually set only `Stat`):
	  • Stat (string)        — Player attribute to bind, e.g. "Hunger" (required)
	  • Max (number)         — fill denominator
	  • Invert (bool)        — fill = 1 - value/Max (bar full = healthy)
	  • WarnAt (number)      — warn when the displayed bar drops below this percent
	  • FillColor/WarnColor (Color3), FillAxis ("X"|"Y")
	  • ValueFormat (string) — numeric readout: "fraction" "99/100" | "percent" "99%"
	                           | "value" "99" | "none" (hide). Defaults to the stat config.
	  • Icon (string)        — icon asset id override (defaults to the stat config / Assets).
	Required child: a GuiObject named `Fill`. Everything else is free-form styling.

	OPTIONAL per-bar children the binder also drives if present (absent => ignored):
	  • TextLabel `Value` — filled with the formatted number (per ValueFormat above).
	  • ImageLabel `Icon` — Image set from the resolved icon id; hidden while the id is "".

	OPTIONAL collapse controls (so the default view shows only the primary bars and the
	rest reveal on click) — all discovered by name/attribute/tag, never by fixed path:
	  • A GuiButton with a `HudToggle` attribute (or tagged "HudToggle") toggles a
	    collapsible container. The attribute's string value names the container; empty
	    falls back to a "Collapsible"-named / "HudCollapsible"-tagged GuiObject.
	  • The container starts Visible=false; the binder flips it and rotates the chevron.
	Everything new is optional, so a minimal HUD (or the fallback) binds exactly as before.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

assert(RunService:IsClient(), "SurvivorCore HUD is client-only — boot it via SurvivorCore.startClient()")

local StatConfig = require(script.Parent.Parent.stats.StatConfig)
local Assets = require(script.Parent.Parent.foundation.Assets)
local HudFallback = require(script.Parent.HudFallback)

local BAR_TAG = "SurvivorStatBar"
local HUD_NAME = "SurvivalHud"
local FALLBACK_WAIT = 1 -- seconds to wait for an authored HUD before building the fallback
local DEFAULT_WARN_COLOR = Color3.fromRGB(200, 40, 40)
local DEFAULT_VALUE_FORMAT = "fraction"
local ICON_CATEGORY = "StatIcons" -- Assets category an owner can populate (key = stat / counter name)
local COUNTER_ATTR = "Counter" -- a bar-less readout (e.g. credits): GuiObject + `Counter` attribute

-- Collapse-control discovery (attribute primary, CollectionService tag as a rename-proof
-- fallback the owner can apply in Studio; the shipped template uses attributes only).
local TOGGLE_NAME = "Toggle"
local TOGGLE_TAG = "HudToggle"
local TOGGLE_ATTR = "HudToggle"
local COLLAPSIBLE_NAME = "Collapsible"
local COLLAPSIBLE_TAG = "HudCollapsible"
local COLLAPSIBLE_ATTR = "HudCollapsible"

-- Resolve the bar's numeric readout string for the given raw value/max. `value` is the
-- RAW stat (not the inverted fill ratio), so an inverted Hunger bar still reads "12/100".
local function formatValue(format: string, value: any, max: number): string
	local n = if typeof(value) == "number" then value else 0
	if format == "none" then
		return ""
	elseif format == "percent" then
		local pct = if max > 0 then math.floor((n / max) * 100 + 0.5) else 0
		return string.format("%d%%", math.clamp(pct, 0, 100))
	elseif format == "value" then
		return tostring(math.floor(n + 0.5))
	end
	-- "fraction" (default / unknown)
	return string.format("%d/%d", math.floor(n + 0.5), math.floor(max + 0.5))
end

-- Resolve a bar's icon id: per-bar `Icon` attribute > stat config `icon` > Assets registry
-- (category "StatIcons", key = stat name). Returns "" when none — never a hardcoded id.
local function resolveIcon(bar: Instance, statName: string, def: any): string
	local id = bar:GetAttribute("Icon")
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	if def and typeof(def.icon) == "string" and def.icon ~= "" then
		return def.icon
	end
	return Assets.tryGet(ICON_CATEGORY, statName) -- silent: "" when unregistered
end

-- Format a counter (e.g. credits) as a grouped integer like "1,234".
local function formatCounter(value: any): string
	local n = if typeof(value) == "number" then math.floor(value + 0.5) else 0
	local digits = tostring(math.abs(n))
	local grouped = ""
	while #digits > 3 do
		grouped = "," .. string.sub(digits, -3) .. grouped
		digits = string.sub(digits, 1, -4)
	end
	grouped = digits .. grouped
	return if n < 0 then "-" .. grouped else grouped
end

local Hud = {}
local started = false

-- installHud() + the StarterGui->PlayerGui copy can briefly produce two HUDs; keep one.
local function dedupeHuds(playerGui: Instance)
	local kept: Instance? = nil
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Name == HUD_NAME then
			if kept then
				gui:Destroy()
			else
				kept = gui
			end
		end
	end
end

function Hud.start(_options: { [string]: any }?)
	if started then
		-- warn-and-return (not assert): the loader may re-run across respawns.
		warn("[SurvivorCore] startClient() called more than once — ignoring")
		return
	end
	started = true

	-- The engine ships its own Health bar, so hide Roblox's built-in top-right health GUI
	-- (it pops in whenever the character takes damage). Retry briefly — CoreGui can refuse
	-- the call in the first frames of a session.
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
			if ok then
				break
			end
			task.wait(0.2)
		end
	end)

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local byName = StatConfig.resolve().byName

	local bound: { [Instance]: () -> () } = {}
	local renderers: { [Instance]: () -> () } = {}

	local function bindBar(bar: Instance)
		local statName = bar:GetAttribute("Stat")
		if typeof(statName) ~= "string" or statName == "" then
			warn(`[SurvivorCore HUD] bar '{bar:GetFullName()}' is missing a 'Stat' attribute`)
			return
		end
		local fill = bar:FindFirstChild("Fill")
		if not fill or not fill:IsA("GuiObject") then
			warn(`[SurvivorCore HUD] bar '{bar:GetFullName()}' is missing a 'Fill' GuiObject child`)
			return
		end
		local fillObject: GuiObject = fill
		local isImage = fillObject:IsA("ImageLabel") or fillObject:IsA("ImageButton")
		local authoredColor = if isImage
			then (fillObject :: ImageLabel).ImageColor3
			else (fillObject :: Frame).BackgroundColor3

		local function setColor(color: Color3)
			if isImage then
				(fillObject :: ImageLabel).ImageColor3 = color
			else
				(fillObject :: Frame).BackgroundColor3 = color
			end
		end

		-- Optional per-bar extras (resolved once; absent => the binder no-ops on them).
		local valueLabel = bar:FindFirstChild("Value")
		local iconLabel = bar:FindFirstChild("Icon")

		local function render()
			local def = byName[statName]
			local max = bar:GetAttribute("Max") or (def and def.max) or 100
			local invert = bar:GetAttribute("Invert")
			if invert == nil then
				invert = (def and def.invert) or false
			end
			local warnAt = bar:GetAttribute("WarnAt") or (def and def.warnAt) or 25
			local axis = bar:GetAttribute("FillAxis") or "X"
			local normalColor = bar:GetAttribute("FillColor") or authoredColor
			local warnColor = bar:GetAttribute("WarnColor") or DEFAULT_WARN_COLOR

			local value = localPlayer:GetAttribute(statName)
			local ratio = 0
			if typeof(value) == "number" and max > 0 then
				ratio = math.clamp(value / max, 0, 1)
			end
			local dangerHigh = bar:GetAttribute("DangerHigh")
			if dangerHigh == nil then
				dangerHigh = (def and def.dangerHigh) or false
			end
			-- Fill shows the RAW value by default (empty at 0), so an affliction like
			-- Hunger/Poison fills UP as it worsens; `invert` flips it for a depleting look.
			local fillRatio = if invert then 1 - ratio else ratio
			-- Warn keys off how close the RAW value is to its dangerous end: resources
			-- (Health/Blood) are dangerous LOW, afflictions (Hunger/Poison) dangerous HIGH.
			local dangerRatio = if dangerHigh then ratio else 1 - ratio

			local size = fillObject.Size
			if axis == "Y" then
				fillObject.Size = UDim2.new(size.X.Scale, size.X.Offset, fillRatio, 0)
			else
				fillObject.Size = UDim2.new(fillRatio, 0, size.Y.Scale, size.Y.Offset)
			end
			setColor(if dangerRatio * 100 >= 100 - warnAt then warnColor else normalColor)

			-- Numeric readout (optional `Value` TextLabel). Uses the RAW value, not the
			-- inverted fill — owners expect "99/100" to mean the real attribute.
			if valueLabel and valueLabel:IsA("TextLabel") then
				local format = bar:GetAttribute("ValueFormat")
				if typeof(format) ~= "string" then
					format = (def and def.valueFormat) or DEFAULT_VALUE_FORMAT
				end
				valueLabel.Text = formatValue(format, value, max)
			end

			-- Icon (optional `Icon` ImageLabel). Blank id => hidden, so a fresh engine
			-- shows no empty box until the owner supplies art.
			if iconLabel and (iconLabel:IsA("ImageLabel") or iconLabel:IsA("ImageButton")) then
				local imageId = resolveIcon(bar, statName, def);
				(iconLabel :: ImageLabel).Image = imageId;
				(iconLabel :: GuiObject).Visible = imageId ~= ""
			end
		end

		local connection = localPlayer:GetAttributeChangedSignal(statName):Connect(render)
		-- also re-render when the bar's own Icon is set at runtime (lets the game assign art live)
		local iconConn = bar:GetAttributeChangedSignal("Icon"):Connect(render)
		renderers[bar] = render
		bound[bar] = function()
			connection:Disconnect()
			iconConn:Disconnect()
		end
		render()
	end

	-- A counter is a bar-less readout (e.g. credits): a GuiObject with a `Counter`
	-- attribute (the Player attribute to show) and a `Value` TextLabel (+ optional `Icon`).
	local function bindCounter(element: Instance)
		local counterName = element:GetAttribute(COUNTER_ATTR)
		if typeof(counterName) ~= "string" or counterName == "" then
			return
		end
		local valueLabel = element:FindFirstChild("Value")
		local iconLabel = element:FindFirstChild("Icon")

		local function render()
			if valueLabel and valueLabel:IsA("TextLabel") then
				valueLabel.Text = formatCounter(localPlayer:GetAttribute(counterName))
			end
			if iconLabel and (iconLabel:IsA("ImageLabel") or iconLabel:IsA("ImageButton")) then
				local imageId = resolveIcon(element, counterName, nil);
				(iconLabel :: ImageLabel).Image = imageId;
				(iconLabel :: GuiObject).Visible = imageId ~= ""
			end
		end

		local connection = localPlayer:GetAttributeChangedSignal(counterName):Connect(render)
		local iconConn = element:GetAttributeChangedSignal("Icon"):Connect(render)
		renderers[element] = render
		bound[element] = function()
			connection:Disconnect()
			iconConn:Disconnect()
		end
		render()
	end

	local function tryBind(bar: Instance)
		if bound[bar] or not bar:IsA("GuiObject") or not bar:IsDescendantOf(playerGui) then
			return
		end
		bindBar(bar)
	end

	local function tryBindCounter(element: Instance)
		if bound[element] or not element:IsA("GuiObject") or not element:IsDescendantOf(playerGui) then
			return
		end
		bindCounter(element)
	end

	dedupeHuds(playerGui)

	-- A stat bar is any GuiObject carrying a `Stat` attribute (how the authored
	-- template marks them) OR tagged `SurvivorStatBar` (for the Builder UI / fallback).
	local function isBar(instance: Instance): boolean
		return instance:IsA("GuiObject") and instance:GetAttribute("Stat") ~= nil
	end

	local function isCounter(instance: Instance): boolean
		return instance:IsA("GuiObject") and instance:GetAttribute(COUNTER_ATTR) ~= nil
	end

	-- A collapse toggle = a GuiButton with a `HudToggle` attribute (or tagged "HudToggle").
	local function isToggle(instance: Instance): boolean
		if not instance:IsA("GuiButton") then
			return false
		end
		return instance:GetAttribute(TOGGLE_ATTR) ~= nil
			or instance.Name == TOGGLE_NAME
			or CollectionService:HasTag(instance, TOGGLE_TAG)
	end

	-- Find the collapsible container a toggle controls. Prefer the container named by the
	-- toggle's `HudToggle` attribute (searched from the toggle's HUD root), else fall back
	-- to a "HudCollapsible"-tagged / `HudCollapsible`-attributed / "Collapsible"-named one.
	local function findCollapsible(button: Instance): Instance?
		local hudRoot = button:FindFirstAncestorWhichIsA("ScreenGui") or playerGui
		local named = button:GetAttribute(TOGGLE_ATTR)
		if typeof(named) == "string" and named ~= "" then
			local found = hudRoot:FindFirstChild(named, true)
			if found and found:IsA("GuiObject") then
				return found
			end
		end
		for _, tagged in CollectionService:GetTagged(COLLAPSIBLE_TAG) do
			if tagged:IsDescendantOf(hudRoot) and tagged:IsA("GuiObject") then
				return tagged
			end
		end
		for _, descendant in hudRoot:GetDescendants() do
			if descendant:IsA("GuiObject") and descendant:GetAttribute(COLLAPSIBLE_ATTR) ~= nil then
				return descendant
			end
		end
		local byNameMatch = hudRoot:FindFirstChild(COLLAPSIBLE_NAME, true)
		if byNameMatch and byNameMatch:IsA("GuiObject") then
			return byNameMatch
		end
		return nil
	end

	local toggles: { [Instance]: () -> () } = {}
	local function wireToggle(button: Instance)
		if toggles[button] or not isToggle(button) or not button:IsDescendantOf(playerGui) then
			return
		end
		local target = findCollapsible(button)
		if not target or not target:IsA("GuiObject") then
			return -- minimal HUDs with a button but no container: skip silently
		end
		local container: GuiObject = target
		local guiButton: GuiButton = button :: GuiButton

		local function apply()
			-- Rotate the same glyph 180° to flip the chevron — no second glyph / asset.
			guiButton.Rotation = if container.Visible then 180 else 0
		end
		apply()
		local connection = guiButton.Activated:Connect(function()
			container.Visible = not container.Visible
			apply()
		end)
		toggles[button] = function()
			connection:Disconnect()
		end
	end

	for _, instance in playerGui:GetDescendants() do
		if isBar(instance) then
			tryBind(instance)
		elseif isCounter(instance) then
			tryBindCounter(instance)
		elseif isToggle(instance) then
			wireToggle(instance)
		end
	end
	playerGui.DescendantAdded:Connect(function(instance)
		if isBar(instance) then
			tryBind(instance)
		elseif isCounter(instance) then
			tryBindCounter(instance)
		elseif isToggle(instance) then
			wireToggle(instance)
		end
	end)
	playerGui.DescendantRemoving:Connect(function(instance)
		local disconnect = bound[instance]
		if disconnect then
			disconnect()
		end
		bound[instance] = nil
		renderers[instance] = nil
		local untoggle = toggles[instance]
		if untoggle then
			untoggle()
			toggles[instance] = nil
		end
	end)

	for _, bar in CollectionService:GetTagged(BAR_TAG) do
		tryBind(bar)
	end
	CollectionService:GetInstanceAddedSignal(BAR_TAG):Connect(tryBind)

	for _, button in CollectionService:GetTagged(TOGGLE_TAG) do
		wireToggle(button)
	end
	CollectionService:GetInstanceAddedSignal(TOGGLE_TAG):Connect(wireToggle)

	-- Re-render bars live when the owner edits the Studio config (WarnAt / Max / colors).
	local function rerenderAll()
		byName = StatConfig.resolve().byName
		for _, render in renderers do
			render()
		end
	end
	local function watch(instance: Instance)
		instance.AttributeChanged:Connect(rerenderAll)
		for _, child in instance:GetChildren() do
			child.AttributeChanged:Connect(rerenderAll)
		end
		instance.ChildAdded:Connect(function(child)
			child.AttributeChanged:Connect(rerenderAll)
			rerenderAll()
		end)
	end
	local configInstance = StatConfig.getConfigInstance()
	if configInstance then
		watch(configInstance)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == StatConfig.CONFIG_INSTANCE_NAME then
			rerenderAll()
			watch(child)
		end
	end)

	-- Zero-setup safety net: if nothing showed up, build the minimal fallback.
	task.delay(FALLBACK_WAIT, function()
		if next(bound) == nil then
			HudFallback.build(playerGui, StatConfig.resolve().stats)
		end
	end)
end

return Hud
