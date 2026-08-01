--!nonstrict
--[[
	SurvivorCore Studio — admin plugin (main).

	ONE floating (dockable) window with a sidebar rail and a detail pane, one page per editor:
	  • Overview      — engine status + content counts (click-through) + how-it-works.
	  • Survival Stats — tune stats (deltas-only, locked) on SurvivalStatsConfig + HUD preview.
	  • Engine Config — every engine Config section (Movement/Combat/Mobs/…/UI theme) as
	                    deltas-only overrides on SurvivorCoreEngineConfig (issue #21).
	  • Content       — create/edit/delete Items/Weapons/Arrows/Resources/Mobs/Quests/Achievements
	                    as SurvivorCoreContent instances, plus OVERRIDES that tune code-registered
	                    defs (issue #40). A rail search box finds any entry by id/name.

	Every mutation is wrapped in a single ChangeHistoryService recording (one undo step), then the
	active page refreshes (others refresh on next show). All real logic lives in the requirable
	modules (StatAdmin / ConfigAdmin / ContentAdmin); the forms in the *Ui modules; the shared look
	in Theme. This is the Builder / Admin plugin (issue #11).
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Theme)
local Nav = require(script.Nav)
local SpawnHelpers = require(script.SpawnHelpers)
local OverviewPage = require(script.OverviewPage)
local SearchPage = require(script.SearchPage)
local StatAdmin = require(script.StatAdmin)
local StatAdminUi = require(script.StatAdminUi)
local HudPreview = require(script.HudPreview)
local ContentAdmin = require(script.ContentAdmin)
local ContentAdminUi = require(script.ContentAdminUi)
local ConfigAdmin = require(script.ConfigAdmin)
local ConfigAdminUi = require(script.ConfigAdminUi)
local BuildAdmin = require(script.BuildAdmin)
local BuildAdminUi = require(script.BuildAdminUi)

local SETTING_LAST_PAGE = "SurvivorCoreStudio.lastPage"

local toolbar = plugin:CreateToolbar("SurvivorCore")
local button = toolbar:CreateButton("Studio", "Tune the engine + create items/weapons/gatherables/mobs (no-code)", "")
button.ClickableWhenViewportHidden = true

-- CreateDockWidgetPluginGui is flagged deprecated by the tooling, but it is still the only API for
-- a dockable plugin widget (there is no replacement) — so allow it here. NOTE: the widget ID is
-- "SurvivorCoreStudio" (was "SurvivorCoreAdmin") — Studio persists dock state PER ID and ignores
-- new initial values for known IDs, so the rename is what makes the floating default reach
-- existing users (their old dock position resets once).
-- selene: allow(deprecated)
local widget = plugin:CreateDockWidgetPluginGui(
	"SurvivorCoreStudio",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 660, 580, 480, 380)
)
widget.Title = "SurvivorCore Studio"
widget.Name = "SurvivorCoreStudio"

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Theme.COLOR.BG
root.BorderSizePixel = 0
root.Parent = widget

local nav -- assigned after the pages are assembled; closures below capture it

-- Wrap a mutation in one ChangeHistory recording (one undo step), then refresh the UI.
local function record(name: string, mutate: () -> any): any
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local result = mutate()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if nav then
		nav.refreshAll()
	end
	return result
end

-- ── Stats callbacks ───────────────────────────────────────────────────────────
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

-- ── Engine Config callbacks ───────────────────────────────────────────────────
local function applyConfigEdit(sectionId: string, groupName: string?, field: any, raw: any, default: any): any
	return record(`Config: {sectionId}.{field.attr}`, function()
		return ConfigAdmin.setOverride(sectionId, groupName, field, raw, default)
	end)
end
local function applyConfigReset(sectionId: string, groupName: string?, attr: string): any
	return record(`Config: reset {sectionId}.{attr}`, function()
		return ConfigAdmin.resetOverride(sectionId, groupName, attr)
	end)
end
local function applyConfigResetSection(section: any): any
	return record(`Config: reset section {section.id}`, function()
		return ConfigAdmin.resetSection(section)
	end)
end

-- ── Build callbacks (world objects: tag + attributes) ────────────────────────
-- One ChangeHistory recording per call, kept strictly at this boundary: BuildAdmin functions must
-- never call each other through here, since a nested TryBeginRecording returns nil.
local buildActions = {
	applyType = function(instances: { Instance }, schema: any, all: { any }): any
		return record(`Build: {BuildAdmin.displayOf(schema).title}`, function()
			return BuildAdmin.applyType(instances, schema, all)
		end)
	end,
	clear = function(instances: { Instance }, all: { any }, extraTags: { string }?): any
		return record("Build: clear component", function()
			return BuildAdmin.clear(instances, all, extraTags)
		end)
	end,
	setField = function(instance: Instance, spec: any, raw: any): any
		return record(`Build: {spec.attr}`, function()
			return BuildAdmin.setField(instance, spec, raw)
		end)
	end,
	resetField = function(instance: Instance, spec: any): any
		return record(`Build: reset {spec.attr}`, function()
			return BuildAdmin.resetField(instance, spec)
		end)
	end,
	-- Not a mutation (no recording): jump to a Content page so a field that references authored
	-- content can send a first-time creator somewhere useful instead of dead-ending.
	selectPage = function(id: string)
		if nav then
			nav.selectPage(id)
		end
	end,
}

-- ── Content callbacks (authored + overrides), bundled for the pages ──────────
local actions = {
	set = function(catKey: string, id: string, field: any, raw: any): any
		return record(`Content: {catKey} {id}.{field.attr}`, function()
			return ContentAdmin.set(catKey, id, field, raw)
		end)
	end,
	create = function(catKey: string, rawId: any): any
		return record(`Content: create {catKey}`, function()
			local ok, message = ContentAdmin.create(catKey, rawId)
			return { ok = ok, message = message }
		end)
	end,
	delete = function(catKey: string, id: string): any
		return record(`Content: delete {catKey} {id}`, function()
			ContentAdmin.delete(catKey, id)
		end)
	end,
	spawn = function(catKey: string, id: string): any
		return record(`Content: add {catKey} '{id}' to world`, function()
			return SpawnHelpers.spawn(ContentAdmin, catKey, id)
		end)
	end,
	createOverride = function(catKey: string, rawId: any): any
		return record(`Content: override {catKey}`, function()
			local ok, message = ContentAdmin.createOverride(catKey, rawId)
			return { ok = ok, message = message }
		end)
	end,
	setOverride = function(catKey: string, id: string, field: any, raw: any): any
		return record(`Content: override {catKey} {id}.{field.attr}`, function()
			return ContentAdmin.setOverrideField(catKey, id, field, raw)
		end)
	end,
	deleteOverride = function(catKey: string, id: string): any
		return record(`Content: remove override {catKey} {id}`, function()
			ContentAdmin.deleteOverride(catKey, id)
		end)
	end,
}

-- ── Search state (rail box → hidden results page) ─────────────────────────────
local currentQuery = ""
local searchGeneration = 0
local lastNonSearchId = "overview"

-- ── NAV assembly (data-driven; new editors slot in as more pages) ─────────────
-- The whole window is built by mountUi() so it can REBUILD: opening an engine-less place yields
-- a single Engine Config explainer page whose Refresh remounts everything once the engine syncs.
local restoring = false

local function mountUi()
	for _, child in root:GetChildren() do
		child:Destroy()
	end

	local pages = {}

	table.insert(pages, {
		id = "overview",
		label = "Overview",
		section = "",
		mount = function(frame)
			return OverviewPage.mount(frame, {
				StatAdmin = StatAdmin,
				ContentAdmin = ContentAdmin,
				selectPage = function(id: string)
					nav.selectPage(id)
				end,
			})
		end,
	})

	-- Build: select a world object → "what is this?" → a schema-rendered setup form. Registered
	-- unconditionally; it renders its own explainer when the engine (or its schemas) is missing.
	table.insert(pages, {
		id = "build",
		label = "Build",
		section = "",
		mount = function(frame)
			return BuildAdminUi.mount(frame, BuildAdmin, ContentAdmin, buildActions)
		end,
	})

	table.insert(pages, {
		id = "stats",
		label = "Survival Stats",
		section = "Stats",
		mount = function(frame)
			return StatAdminUi.mount(frame, StatAdmin, applyEdit, applyReset, applyPreview, applyClear)
		end,
	})

	local configPages = ConfigAdminUi.pages(
		ConfigAdmin,
		applyConfigEdit,
		applyConfigReset,
		applyConfigResetSection,
		function() -- onEngineFound: remount with the full section list
			task.defer(mountUi)
		end
	)
	for _, page in configPages do
		table.insert(pages, page)
	end

	for _, catKey in ContentAdmin.ORDER do
		local cat = ContentAdmin.CATEGORIES[catKey]
		table.insert(pages, {
			id = "content/" .. catKey,
			label = cat.title,
			section = "Content",
			badge = function()
				return #ContentAdmin.listRoster(catKey)
			end,
			mount = function(frame)
				return ContentAdminUi.mountCategory(frame, catKey, ContentAdmin, actions)
			end,
		})
	end

	table.insert(pages, {
		id = "search",
		label = "Search",
		section = "",
		hidden = true,
		mount = function(frame)
			return SearchPage.mount(frame, {
				ContentAdmin = ContentAdmin,
				ContentAdminUi = ContentAdminUi,
				actions = actions,
				getQuery = function()
					return currentQuery
				end,
			})
		end,
	})

	-- Restore the last-open page (validated against the live page list — ids may change across
	-- plugin versions or when the engine's schema grows/shrinks).
	local restoredId = "overview"
	local saved = plugin:GetSetting(SETTING_LAST_PAGE)
	if typeof(saved) == "string" then
		for _, page in pages do
			if page.id == saved and not page.hidden then
				restoredId = saved
				break
			end
		end
	end

	-- The mount-time selectPage must NOT write the setting: an engine-less session falls back to
	-- "overview", and persisting that would clobber a saved config page the user will want back.
	restoring = true
	nav = Nav.mount(root, pages, {
		initialId = restoredId,
		onNavigate = function(id: string)
			lastNonSearchId = id
			searchGeneration += 1 -- explicit navigation cancels any pending search-page jump
			if restoring then
				return
			end
			if plugin:GetSetting(SETTING_LAST_PAGE) ~= id then
				plugin:SetSetting(SETTING_LAST_PAGE, id)
			end
		end,
		onSearch = function(text: string)
			currentQuery = text
			searchGeneration += 1
			local generation = searchGeneration
			task.delay(0.25, function()
				if generation ~= searchGeneration or not widget.Enabled then
					return
				end
				if string.match(currentQuery, "^%s*$") then
					if nav.getActiveId() == "search" then
						nav.selectPage(lastNonSearchId)
					end
				else
					nav.selectPage("search")
					nav.refreshAll() -- re-render the results with the new query
				end
			end)
		end,
	})
	restoring = false
end

mountUi()

-- An undo/redo can revert any edit the pages show — refresh so they never go stale. Skip while
-- the user is mid-edit in one of OUR text boxes (the rebuild would destroy the focused box and
-- eat the typed text); the per-page Refresh button covers that rare overlap.
local function onHistoryChanged()
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(widget) then
		return
	end
	if nav then
		nav.refreshAll()
	end
end
ChangeHistoryService.OnUndo:Connect(onHistoryChanged)
ChangeHistoryService.OnRedo:Connect(onHistoryChanged)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		nav.refreshAll()
	end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)
