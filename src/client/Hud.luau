--[[
	Hud — the client HUD binder. CLIENT-ONLY.

	Drives any `SurvivorStatBar`-tagged GUI from the player's stat Attributes (which
	the server writes and Roblox auto-replicates — no RemoteEvents). The owner authors
	and re-textures the actual ScreenGui in StarterGui; this only ever sets each bar's
	`Fill` size + color, so restyling needs zero code.

	Per-bar contract (attributes on the tagged Frame; most default from the stat config,
	so owners usually set only `Stat`):
	  • Stat (string)    — Player attribute to bind, e.g. "Hunger" (required)
	  • Max (number)     — fill denominator
	  • Invert (bool)    — fill = 1 - value/Max (bar full = healthy)
	  • WarnAt (number)  — warn when the displayed bar drops below this percent
	  • FillColor/WarnColor (Color3), FillAxis ("X"|"Y")
	Required child: a GuiObject named `Fill`. Everything else is free-form styling.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsClient(), "SurvivorCore HUD is client-only — boot it via SurvivorCore.startClient()")

local StatConfig = require(script.Parent.Parent.stats.StatConfig)
local HudFallback = require(script.Parent.HudFallback)

local BAR_TAG = "SurvivorStatBar"
local HUD_NAME = "SurvivalHud"
local FALLBACK_WAIT = 1 -- seconds to wait for an authored HUD before building the fallback
local DEFAULT_WARN_COLOR = Color3.fromRGB(200, 40, 40)

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
			local fillRatio = if invert then 1 - ratio else ratio

			local size = fillObject.Size
			if axis == "Y" then
				fillObject.Size = UDim2.new(size.X.Scale, size.X.Offset, fillRatio, 0)
			else
				fillObject.Size = UDim2.new(fillRatio, 0, size.Y.Scale, size.Y.Offset)
			end
			setColor(if fillRatio * 100 < warnAt then warnColor else normalColor)
		end

		local connection = localPlayer:GetAttributeChangedSignal(statName):Connect(render)
		renderers[bar] = render
		bound[bar] = function()
			connection:Disconnect()
		end
		render()
	end

	local function tryBind(bar: Instance)
		if bound[bar] or not bar:IsA("GuiObject") or not bar:IsDescendantOf(playerGui) then
			return
		end
		bindBar(bar)
	end

	dedupeHuds(playerGui)

	-- A stat bar is any GuiObject carrying a `Stat` attribute (how the authored
	-- template marks them) OR tagged `SurvivorStatBar` (for the Builder UI / fallback).
	local function isBar(instance: Instance): boolean
		return instance:IsA("GuiObject") and instance:GetAttribute("Stat") ~= nil
	end

	for _, instance in playerGui:GetDescendants() do
		if isBar(instance) then
			tryBind(instance)
		end
	end
	playerGui.DescendantAdded:Connect(function(instance)
		if isBar(instance) then
			tryBind(instance)
		end
	end)
	playerGui.DescendantRemoving:Connect(function(instance)
		local disconnect = bound[instance]
		if disconnect then
			disconnect()
		end
		bound[instance] = nil
		renderers[instance] = nil
	end)

	for _, bar in CollectionService:GetTagged(BAR_TAG) do
		tryBind(bar)
	end
	CollectionService:GetInstanceAddedSignal(BAR_TAG):Connect(tryBind)

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
