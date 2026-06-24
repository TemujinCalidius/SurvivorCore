--!nonstrict
--[[
	SurvivorCore — admin plugin (main).

	ONE dock widget, a tab bar across the top, one feature per tab:
	  • Stats   — tune the survival stats (deltas-only, locked) on SurvivalStatsConfig + HUD preview.
	  • Content — create/edit/delete Items + Gatherable resources (no-code) as SurvivorCoreContent
	              instances the engine loads at start().
	Every mutation is wrapped in a single ChangeHistoryService recording (one undo step) and then
	both editors refresh. All real logic lives in the requirable modules (StatAdmin / ContentAdmin);
	the forms in StatAdminUi / ContentAdminUi. This is the Builder / Admin plugin (issue #11), and
	new sections (Movement / Consequences, #21) slot in as more tabs.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local StatAdmin = require(script.StatAdmin)
local StatAdminUi = require(script.StatAdminUi)
local HudPreview = require(script.HudPreview)
local ContentAdmin = require(script.ContentAdmin)
local ContentAdminUi = require(script.ContentAdminUi)

local COL_BG = Color3.fromRGB(18, 21, 28)
local COL_TAB = Color3.fromRGB(28, 32, 42)
local COL_TAB_ON = Color3.fromRGB(52, 58, 74)
local COL_TEXT = Color3.fromRGB(235, 238, 245)
local TAB_H = 30

local toolbar = plugin:CreateToolbar("SurvivorCore")
local button = toolbar:CreateButton("Admin Panel", "Tune stats + create items/gatherables (no-code)", "")
button.ClickableWhenViewportHidden = true

-- CreateDockWidgetPluginGui is flagged deprecated by the tooling, but it is still the only API for
-- a dockable plugin widget (there is no replacement) — so allow it here.
-- selene: allow(deprecated)
local widget = plugin:CreateDockWidgetPluginGui(
	"SurvivorCoreAdmin",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 560, 320, 400)
)
widget.Title = "SurvivorCore Admin"
widget.Name = "SurvivorCoreAdmin"

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = COL_BG
root.BorderSizePixel = 0
root.Parent = widget

-- Tab bar + content region.
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
tabBar.BackgroundColor3 = COL_BG
tabBar.BorderSizePixel = 0
tabBar.Parent = root
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar
local tabPad = Instance.new("UIPadding")
tabPad.PaddingLeft = UDim.new(0, 8)
tabPad.PaddingTop = UDim.new(0, 4)
tabPad.Parent = tabBar

local region = Instance.new("Frame")
region.Position = UDim2.fromOffset(0, TAB_H)
region.Size = UDim2.new(1, 0, 1, -TAB_H)
region.BackgroundTransparency = 1
region.BorderSizePixel = 0
region.Parent = root

local statFrame = Instance.new("Frame")
statFrame.Size = UDim2.fromScale(1, 1)
statFrame.BackgroundTransparency = 1
statFrame.Parent = region

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.fromScale(1, 1)
contentFrame.BackgroundTransparency = 1
contentFrame.Visible = false
contentFrame.Parent = region

local statUi: { refresh: () -> () }? = nil
local contentUi: { refresh: () -> () }? = nil

-- Wrap a mutation in one ChangeHistory recording (one undo step), then refresh both editors.
local function record(name: string, mutate: () -> any): any
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local result = mutate()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if statUi then
		statUi.refresh()
	end
	if contentUi then
		contentUi.refresh()
	end
	return result
end

-- Stats callbacks.
local function applyEdit(statName: string, attr: string, raw: any, default: any): any
	return record(`Stats: {statName}.{attr}`, function()
		return StatAdmin.setOverride(statName, attr, raw, default)
	end)
end
local function applyReset(statName: string, attr: string): any
	return record(`Stats: reset {statName}.{attr}`, function()
		return StatAdmin.resetOverride(statName, attr)
	end)
end
local function applyPreview(): any
	return record("Stats: preview HUD", function()
		return HudPreview.apply(StatAdmin)
	end)
end
local function applyClear(): any
	return record("Stats: clear HUD preview", function()
		return HudPreview.clear()
	end)
end

-- Content callbacks.
local function applySet(catKey: string, id: string, field: any, raw: any): any
	return record(`Content: {catKey} {id}.{field.attr}`, function()
		return ContentAdmin.set(catKey, id, field, raw)
	end)
end
local function applyCreate(catKey: string, rawId: any): any
	return record(`Content: create {catKey}`, function()
		return ContentAdmin.create(catKey, rawId)
	end)
end
local function applyDelete(catKey: string, id: string): any
	return record(`Content: delete {catKey} {id}`, function()
		ContentAdmin.delete(catKey, id)
	end)
end

-- "Add to World": drop a tagged, Resource-set Part in front of the camera, then select it. The
-- no-code way to place a gatherable node — tag + Resource attribute is exactly what the engine reads.
local function applySpawn(id: string): any
	return record(`Content: add gatherable '{id}' to world`, function()
		local part = Instance.new("Part")
		part.Name = id
		part.Size = Vector3.new(4, 4, 4)
		part.Anchored = true
		local cam = Workspace.CurrentCamera
		part.Position = if cam then cam.CFrame.Position + cam.CFrame.LookVector * 16 else Vector3.new(0, 5, 0)
		part:SetAttribute("Resource", id)
		CollectionService:AddTag(part, "Gatherable")
		part.Parent = Workspace
		Selection:Set({ part })
		return part
	end)
end

statUi = StatAdminUi.mount(statFrame, StatAdmin, applyEdit, applyReset, applyPreview, applyClear)
contentUi = ContentAdminUi.mount(contentFrame, ContentAdmin, applySet, applyCreate, applyDelete, applySpawn)

-- Tabs.
local TABS = {
	{ id = "stats", label = "Stats", frame = statFrame },
	{ id = "content", label = "Content", frame = contentFrame },
}
local tabButtons: { [string]: TextButton } = {}

local function showTab(id: string)
	for _, t in TABS do
		t.frame.Visible = t.id == id
		local b = tabButtons[t.id]
		if b then
			b.BackgroundColor3 = if t.id == id then COL_TAB_ON else COL_TAB
		end
	end
end

for _, t in TABS do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(92, TAB_H - 6)
	b.BackgroundColor3 = COL_TAB
	b.AutoButtonColor = true
	b.Text = t.label
	b.TextColor3 = COL_TEXT
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.BorderSizePixel = 0
	b.Parent = tabBar
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = b
	tabButtons[t.id] = b
	b.MouseButton1Click:Connect(function()
		showTab(t.id)
	end)
end
showTab("stats")

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		if statUi then
			statUi.refresh()
		end
		if contentUi then
			contentUi.refresh()
		end
	end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)
