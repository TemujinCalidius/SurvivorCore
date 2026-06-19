--!nonstrict
--[[
	SurvivorCore — Survival Stats admin plugin (main).

	A toolbar button toggles a dock widget that edits the survival-stats `SurvivalStatsConfig`
	instance through StatAdmin — the deltas-only, LOCKED model: it writes only fields the owner
	changes from the engine default, removes them on reset, and can NEVER write the engine-owned
	semantics (Invert / DangerHigh). Edits are wrapped in ChangeHistoryService recordings so each
	is a single undo step. All real logic lives in StatAdmin (testable); the form in StatAdminUi.

	First slice of the Builder / Admin plugin (issue #11).
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local StatAdmin = require(script.StatAdmin)
local StatAdminUi = require(script.StatAdminUi)
local HudPreview = require(script.HudPreview)

local toolbar = plugin:CreateToolbar("SurvivorCore")
local button = toolbar:CreateButton("Survival Stats", "Tune survival-stat rates, thresholds and HUD options", "")
button.ClickableWhenViewportHidden = true

-- CreateDockWidgetPluginGui is flagged deprecated by the tooling, but it is still the only
-- API for a dockable plugin widget (there is no replacement) — so allow it here.
-- selene: allow(deprecated)
local widget = plugin:CreateDockWidgetPluginGui(
	"SurvivorCoreStatAdmin",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 520, 280, 360)
)
widget.Title = "Survival Stats"
widget.Name = "SurvivorCoreStatAdmin"

local container = Instance.new("Frame")
container.Size = UDim2.fromScale(1, 1)
container.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
container.BorderSizePixel = 0
container.Parent = widget

local ui: { refresh: () -> () }? = nil

-- Wrap a single StatAdmin mutation in one ChangeHistory recording (so it's one undo step),
-- then refresh the form so the override indicators reflect the new state.
local function record(name: string, mutate: () -> any): any
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local result = mutate()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if ui then
		ui.refresh()
	end
	return result
end

local function applyEdit(statName: string, attr: string, raw: any, default: any): any
	return record(`Survival Stats: {statName}.{attr}`, function()
		return StatAdmin.setOverride(statName, attr, raw, default)
	end)
end

local function applyReset(statName: string, attr: string): any
	return record(`Survival Stats: reset {statName}.{attr}`, function()
		return StatAdmin.resetOverride(statName, attr)
	end)
end

-- Edit-mode HUD preview (paints resolved icons + sample fills onto the StarterGui HUD) and its
-- undo-able restore. Each is one ChangeHistory step; both return the HudPreview result so the
-- footer can show a status.
local function applyPreview(): any
	return record("Survival Stats: preview HUD", function()
		return HudPreview.apply(StatAdmin)
	end)
end

local function applyClear(): any
	return record("Survival Stats: clear HUD preview", function()
		return HudPreview.clear()
	end)
end

ui = StatAdminUi.mount(container, StatAdmin, applyEdit, applyReset, applyPreview, applyClear)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled and ui then
		ui.refresh()
	end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)
